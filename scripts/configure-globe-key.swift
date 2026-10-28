#!/usr/bin/env swift
import Foundation

// These are the same Carbon entry points used by macOS Keyboard Settings on macOS 26.
// Values shown by that pane are: 1 = Change Input Source, 2 = Show Emoji & Symbols,
// and 3 = Start Dictation.
@_silgen_name("TISGetFnUsageType")
private func TISGetFnUsageType() -> UInt32

@_silgen_name("TISUpdateFnUsageType")
private func TISUpdateFnUsageType(_ usageType: UInt32)

private let emojiAndSymbolsUsageType: UInt32 = 2

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ERROR: \(message)\n".utf8))
    exit(1)
}

private func currentUsageType() -> UInt32 {
    TISGetFnUsageType()
}

switch CommandLine.arguments.dropFirst().first {
case "--read":
    print(currentUsageType())

case "--set-emoji":
    let previous = currentUsageType()
    if previous != emojiAndSymbolsUsageType {
        TISUpdateFnUsageType(emojiAndSymbolsUsageType)
    }
    let current = currentUsageType()
    guard current == emojiAndSymbolsUsageType else {
        fail("Globe key action is \(current); expected \(emojiAndSymbolsUsageType) for Emoji & Symbols.")
    }
    print("Globe key action verified: Emoji & Symbols (\(current)); previous=\(previous)")

case "--require-emoji":
    let current = currentUsageType()
    guard current == emojiAndSymbolsUsageType else {
        fail("Globe key action is \(current); expected \(emojiAndSymbolsUsageType) for Emoji & Symbols.")
    }
    print("Globe key action verified: Emoji & Symbols (\(current))")

default:
    fail("Usage: configure-globe-key.swift --read | --set-emoji | --require-emoji")
}
