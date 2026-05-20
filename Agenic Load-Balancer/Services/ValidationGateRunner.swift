//
//  ValidationGateRunner.swift
//  Agenic Load-Balancer
//
//  Phase 7.6: validation gate values and test doubles.
//

import Foundation

struct ValidationGateResult: Sendable, Hashable {
    var command: String
    var exitCode: Int32
    var outputExcerpt: String
    var startedAt: Date
    var endedAt: Date

    var passed: Bool { exitCode == 0 }
}

protocol ValidationGateRunning: Sendable {
    func run(command: String, workingDirectory: String) async -> ValidationGateResult
}

struct ScriptedValidationGateRunner: ValidationGateRunning {
    let result: ValidationGateResult

    func run(command _: String, workingDirectory _: String) async -> ValidationGateResult {
        result
    }
}
