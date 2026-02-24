//
//  PersonalRecordsDebugView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/20/25.
//
//  Debug view to inspect personal records

import SwiftUI
import SwiftData

struct PersonalRecordsDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var allRecords: [PersonalRecord]
    @State private var settingsManager = SettingsManager.shared
    
    var currentRecords: [PersonalRecord] {
        allRecords.filter { $0.isCurrent }
    }
    
    var historicalRecords: [PersonalRecord] {
        allRecords.filter { !$0.isCurrent }
    }
    
    var body: some View {
        List {
            Section("Current Personal Records (\(currentRecords.count))") {
                if currentRecords.isEmpty {
                    Text("No personal records yet")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(currentRecords, id: \.id) { record in
                        recordRow(record)
                    }
                }
            }
            
            Section("Historical Records (\(historicalRecords.count))") {
                if historicalRecords.isEmpty {
                    Text("No historical records")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(historicalRecords, id: \.id) { record in
                        recordRow(record)
                            .opacity(0.6)
                    }
                }
            }
            
            Section("Actions") {
                Button(role: .destructive) {
                    clearAllRecords()
                } label: {
                    Label("Clear All Personal Records", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Personal Records Debug")
    }
    
    private func recordRow(_ record: PersonalRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.type.emoji)
                Text(record.type.displayName)
                    .font(.headline)
                Spacer()
                if record.isCurrent {
                    Text("CURRENT")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .clipShape(.rect(cornerRadius: 4))
                }
            }
            
            Text(record.formattedValue(measurementSystem: settingsManager.measurementSystem))
                .font(.title2)
                .bold()
            
            Text(record.workoutName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text(record.achievedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let previousId = record.previousRecordId {
                Text("Beat previous record: \(previousId.uuidString.prefix(8))...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func clearAllRecords() {
        for record in allRecords {
            modelContext.delete(record)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Error clearing records: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        PersonalRecordsDebugView()
            .modelContainer(for: PersonalRecord.self, inMemory: true)
    }
}

