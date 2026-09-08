// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchSystemView: View {
    let select: (MetricDetailKind) -> Void
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var l10n = L10n.shared
    private var snapshot: SystemSnapshot { monitor.snapshot }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            if AppFeature.monitorCPU.isAvailable {
                metric(.cpu, l10n.s.cpuLabel, symbol: "cpu", value: percent(snapshot.cpuUsage), level: snapshot.cpuUsage)
            }
            if AppFeature.monitorGPU.isAvailable {
                metric(.gpu, l10n.s.gpuLabel, symbol: "rectangle.connected.to.line.below",
                       value: percent(snapshot.gpuUsage), level: snapshot.gpuUsage)
            }
            if AppFeature.monitorMemory.isAvailable {
                let ratio = snapshot.memoryUsed.flatMap { used in
                    snapshot.memoryTotal.flatMap { total in total > 0 ? Double(used) / Double(total) : nil }
                }
                metric(.memory, l10n.s.memorySection, symbol: "memorychip", value: percent(ratio), level: ratio)
            }
            if AppFeature.monitorPower.isAvailable, let power = snapshot.power, power.hasBattery {
                metric(.battery, l10n.s.batteryLabel,
                       symbol: power.externalConnected ? "battery.100percent.bolt" : "battery.100percent",
                       value: power.chargePercent.map { "\($0)%" },
                       level: power.chargePercent.map { Double($0) / 100 })
            }
            if AppFeature.monitorNetwork.isAvailable {
                metric(.network, l10n.s.networkDownload, symbol: "arrow.down", value: snapshot.netDownBytesPerSec.map(MetricFormat.bytesPerSec))
                metric(.network, l10n.s.networkUpload, symbol: "arrow.up", value: snapshot.netUpBytesPerSec.map(MetricFormat.bytesPerSec))
            }
        }
    }

    private func percent(_ value: Double?) -> String? {
        value.map { "\(Int(($0 * 100).rounded()))%" }
    }

    private func metric(_ kind: MetricDetailKind, _ title: String, symbol: String, value: String?, level: Double? = nil) -> some View {
        Button { select(kind) } label: {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary).lineLimit(1)
            Text(value ?? "…").font(.system(size: 20, weight: .medium, design: .rounded))
                .monospacedDigit().contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
            if let level {
                ProgressView(value: min(1, max(0, level))).progressViewStyle(.linear)
                    .controlSize(.mini).tint(.white.opacity(0.65)).frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(8).background(.black, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.14), lineWidth: 0.6) }
        }.buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value ?? "…")
    }
}
