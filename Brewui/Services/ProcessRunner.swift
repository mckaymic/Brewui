//
//  ProcessRunner.swift
//  Brewui
//
//  Created by Michael McKay on 1/11/26.
//

import Foundation

/// Result of a process execution
struct ProcessResult: Sendable {
    let exitCode: Int32
    let output: String
    let errorOutput: String
    
    nonisolated var isSuccess: Bool {
        exitCode == 0
    }
    
    nonisolated var combinedOutput: String {
        if errorOutput.isEmpty {
            return output
        } else if output.isEmpty {
            return errorOutput
        }
        return "\(output)\n\(errorOutput)"
    }
}

/// Error types for process execution
enum ProcessRunnerError: LocalizedError, Sendable {
    case commandNotFound(String)
    case executionFailed(exitCode: Int32, message: String)
    case timeout
    case cancelled
    
    nonisolated var errorDescription: String? {
        switch self {
        case .commandNotFound(let cmd):
            return "Command not found: \(cmd)"
        case .executionFailed(let code, let message):
            return "Command failed (exit code \(code)): \(message)"
        case .timeout:
            return "Command timed out"
        case .cancelled:
            return "Command was cancelled"
        }
    }
}

/// Executes shell commands asynchronously
actor ProcessRunner {
    
    static let shared = ProcessRunner()
    
    private init() {}
    
    /// Runs a command and returns the result
    /// - Parameters:
    ///   - command: The command to execute (e.g., "/opt/homebrew/bin/brew")
    ///   - arguments: Command arguments
    ///   - environment: Additional environment variables
    ///   - timeout: Maximum execution time in seconds (nil for no timeout)
    /// - Returns: ProcessResult containing output and exit code
    nonisolated func run(
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        try await runWithStreaming(
            command: command,
            arguments: arguments,
            environment: environment,
            timeout: timeout,
            outputHandler: nil
        )
    }
    
    /// Runs a command with real-time streaming output
    /// - Parameters:
    ///   - command: The command to execute (e.g., "/opt/homebrew/bin/brew")
    ///   - arguments: Command arguments
    ///   - environment: Additional environment variables
    ///   - timeout: Maximum execution time in seconds (nil for no timeout)
    ///   - outputHandler: Called with output text as it arrives (on main thread)
    /// - Returns: ProcessResult containing final output and exit code
    nonisolated func runWithStreaming(
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil,
        outputHandler: (@MainActor (String) -> Void)?
    ) async throws -> ProcessResult {
        
        print("[ProcessRunner] Running: \(command) \(arguments.joined(separator: " "))")
        
        // Check if command exists
        if !FileManager.default.fileExists(atPath: command) {
            print("[ProcessRunner] Command not found: \(command)")
            throw ProcessRunnerError.commandNotFound(command)
        }
        
        // Create a sendable wrapper for the output handler
        let handler = outputHandler
        
        // Run the process using withCheckedThrowingContinuation to bridge sync/async
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                // Set up environment
                var env = ProcessInfo.processInfo.environment
                // Ensure PATH includes common Homebrew locations
                let homebrewPaths = "/opt/homebrew/bin:/usr/local/bin"
                if let existingPath = env["PATH"] {
                    env["PATH"] = "\(homebrewPaths):\(existingPath)"
                } else {
                    env["PATH"] = homebrewPaths
                }
                
                // Add any custom environment variables
                if let customEnv = environment {
                    for (key, value) in customEnv {
                        env[key] = value
                    }
                }
                process.environment = env
                
                // Variables to collect output
                var outputData = Data()
                var errorData = Data()
                
                // Read stdout asynchronously to prevent buffer deadlock
                let outputHandle = outputPipe.fileHandleForReading
                let errorHandle = errorPipe.fileHandleForReading
                
                // Use DispatchGroup to wait for both reads to complete
                let group = DispatchGroup()
                
                // Read stdout in background with streaming
                group.enter()
                DispatchQueue.global().async {
                    if let handler = handler {
                        // Streaming mode - read data as it comes
                        while true {
                            let availableData = outputHandle.availableData
                            if availableData.isEmpty {
                                break
                            }
                            outputData.append(availableData)
                            
                            // Send to handler on main thread
                            if let text = String(data: availableData, encoding: .utf8), !text.isEmpty {
                                Task { @MainActor in
                                    handler(text)
                                }
                            }
                        }
                    } else {
                        // Non-streaming mode - read all at once
                        outputData = outputHandle.readDataToEndOfFile()
                    }
                    group.leave()
                }
                
                // Read stderr in background with streaming
                group.enter()
                DispatchQueue.global().async {
                    if let handler = handler {
                        // Streaming mode - read data as it comes
                        while true {
                            let availableData = errorHandle.availableData
                            if availableData.isEmpty {
                                break
                            }
                            errorData.append(availableData)
                            
                            // Send to handler on main thread
                            if let text = String(data: availableData, encoding: .utf8), !text.isEmpty {
                                Task { @MainActor in
                                    handler(text)
                                }
                            }
                        }
                    } else {
                        // Non-streaming mode - read all at once
                        errorData = errorHandle.readDataToEndOfFile()
                    }
                    group.leave()
                }
                
                // Start the process
                print("[ProcessRunner] Starting process...")
                do {
                    try process.run()
                } catch {
                    print("[ProcessRunner] Failed to start process: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                print("[ProcessRunner] Process started with PID: \(process.processIdentifier)")
                
                // Set up timeout if specified
                var didTimeout = false
                let timeoutWorkItem: DispatchWorkItem?
                if let timeout = timeout {
                    let workItem = DispatchWorkItem {
                        if process.isRunning {
                            print("[ProcessRunner] Timeout reached, terminating process")
                            didTimeout = true
                            process.terminate()
                        }
                    }
                    timeoutWorkItem = workItem
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: workItem)
                } else {
                    timeoutWorkItem = nil
                }
                
                // Wait for the process to complete
                process.waitUntilExit()
                
                // Cancel the timeout
                timeoutWorkItem?.cancel()
                
                // Wait for output reading to complete
                group.wait()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                
                print("[ProcessRunner] Process finished with exit code: \(process.terminationStatus)")
                print("[ProcessRunner] Output length: \(output.count) chars, Error length: \(errorOutput.count) chars")
                
                if didTimeout {
                    continuation.resume(throwing: ProcessRunnerError.timeout)
                    return
                }
                
                continuation.resume(returning: ProcessResult(
                    exitCode: process.terminationStatus,
                    output: output.trimmingCharacters(in: .whitespacesAndNewlines),
                    errorOutput: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }
    }
    
    /// Runs a shell command string using /bin/bash
    /// - Parameters:
    ///   - shellCommand: The full shell command to execute
    ///   - timeout: Maximum execution time in seconds
    /// - Returns: ProcessResult containing output and exit code
    nonisolated func runShell(
        _ shellCommand: String,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        return try await run(
            command: "/bin/bash",
            arguments: ["-c", shellCommand],
            timeout: timeout
        )
    }
    
    /// Checks if a command exists at the specified path
    nonisolated func commandExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
    
    /// Finds the path to a command using `which`
    nonisolated func findCommand(_ name: String) async -> String? {
        do {
            let result = try await runShell("which \(name)")
            if result.isSuccess && !result.output.isEmpty {
                return result.output
            }
        } catch {
            // Command not found
        }
        return nil
    }
}
