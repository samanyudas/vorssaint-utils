// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var music = NotchMusicService.shared
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var draggingModule: NotchModule?
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }

    var body: some View {
        surface
            .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
            .background(.black)
            .foregroundStyle(.white)
            .overlay {
                shape.stroke(.white.opacity(service.expanded || service.peeking || service.notice != nil || service.captureControls != nil
                                            ? (contrast == .increased ? 0.4 : 0.12) : 0), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
            .onHover(perform: service.hover)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .environment(\.notchPresentation, true)
            .tint(.white)
            .accessibilityIdentifier("notch.surface")
    }

    private var shape: NotchShape {
        NotchShape(attached: service.geometry.isNotched,
                   radius: min(24, service.surfaceSize.height / 2))
    }

    @ViewBuilder private var surface: some View {
        if let options = service.captureControls {
            NotchCaptureControlsView(options: options, service: service)
                .padding(.horizontal, 18).padding(.top, service.geometry.safeContentTop)
        } else if service.expanded {
            expanded
        } else if service.dragPlaceholder {
            Label(text.dropHint, systemImage: "tray.and.arrow.down")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.top, service.geometry.safeContentTop)
        } else if let notice = service.notice {
            Button {
                service.open(notice.event == .clipboard ? .clipboard : .controls)
            } label: {
                NotchNoticeView(notice: notice)
                    .padding(.horizontal, 20)
                    .padding(.top, service.geometry.safeContentTop)
                    .padding(.bottom, 14)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(notice.title) \(notice.detail)")
            .accessibilityHint(text.open)
            .transition(.opacity)
        } else if service.peeking {
            navigation.padding(.horizontal, 14).padding(.top, service.geometry.safeContentTop)
        } else if service.hasMusicActivity {
            NotchMusicStrip(service: service)
        } else {
            compact
                .transition(.opacity)
        }
    }

    private var compact: some View {
        Button { service.open() } label: {
            HStack(spacing: 0) {
                if service.idleContent != .none, service.geometry.restingWingWidth > 0 {
                    Group {
                        switch service.idleContent {
                        case .music:
                            if let artwork = music.artwork {
                                Image(nsImage: artwork).resizable().scaledToFill()
                                    .frame(width: min(22, service.geometry.menuBarHeight - 6), height: min(22, service.geometry.menuBarHeight - 6))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        case .battery: Image(systemName: "battery.100percent").font(.system(size: 12))
                        case .controls: Image(systemName: "slider.horizontal.3").font(.system(size: 12))
                        case .none: EmptyView()
                        }
                    }.frame(width: service.geometry.restingWingWidth)
                    Color.clear.frame(width: service.geometry.cameraWidth)
                    Group {
                        switch service.idleContent {
                        case .music:
                            if music.playback?.isPlaying == true { Image(systemName: "waveform").foregroundStyle(.mint) }
                        case .battery:
                            if let percent = service.power.chargePercent {
                                Text("\(percent)%").font(.system(size: 9, weight: .medium)).monospacedDigit()
                            }
                        case .controls: Image(systemName: "chevron.down").font(.system(size: 9))
                        case .none: EmptyView()
                        }
                    }.frame(width: service.geometry.restingWingWidth)
                } else { Color.clear }
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text.open)
        .help(text.open)
    }

    private var showsDetail: Bool { service.showingAppPanel || service.selectedMetric != nil }

    private var expanded: some View {
        VStack(spacing: 10) {
            if showsDetail { header }
            if service.showingAppPanel || service.selected == .files || service.selected == .music
                || (service.selected == .captures && service.captureContent == nil) {
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if (service.selected == .controls || service.selected == .system || service.selected == .tools), service.selectedMetric == nil {
                ViewThatFits(in: .vertical) {
                    content.fixedSize(horizontal: false, vertical: true)
                    ScrollView {
                        content.fixedSize(horizontal: false, vertical: true)
                    }.scrollIndicators(.automatic)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.bottom, 4)
                }
                .scrollIndicators(.automatic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !showsDetail {
                navigation
                header
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, service.geometry.safeContentTop)
        .padding(.bottom, 14)
        .frame(width: service.expandedSize.width, height: service.expandedSize.height, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if service.showingAppPanel || service.selectedMetric != nil {
                NotchIconButton(symbol: "chevron.left", title: l10n.s.obBack) {
                    service.goBack()
                }
            }
            if let notice = service.notice {
                Label("\(notice.title)  \(notice.detail)", systemImage: notice.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .accessibilityAddTraits(.updatesFrequently)
            } else {
                Text(service.showingAppPanel ? "Vorssaint" : service.selectedMetric?.title(l10n.s) ?? service.selected.title(l10n.language))
                    .font(.system(size: showsDetail ? 14 : 11, weight: showsDetail ? .semibold : .medium))
                    .foregroundStyle(showsDetail ? .primary : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            NotchIconButton(symbol: service.pinned ? "pin.fill" : "pin",
                            title: service.pinned ? text.unpin : text.pin) {
                service.pinned.toggle()
            }
            NotchIconButton(symbol: "gearshape", title: l10n.s.menuSettings, action: service.openSettings)
            NotchIconButton(symbol: "chevron.up", title: text.collapse, action: service.collapse)
        }
        .frame(height: 24)
    }

    private var navigation: some View {
        HStack(spacing: 4) {
            ForEach(service.modules) { module in
                PanelReorderableItem(item: module, isEnabled: true,
                    order: Binding(get: { service.modules }, set: { modules in
                        UserDefaults.standard.set(modules.map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.notchModuleOrder)
                    }), dragging: $draggingModule) {
                Button { service.select(module) } label: {
                    Image(systemName: module.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(service.selected == module ? .white : .white.opacity(0.5))
                        .background(.black, in: RoundedRectangle(cornerRadius: 9))
                        .overlay { RoundedRectangle(cornerRadius: 9)
                            .stroke(.white.opacity(service.selected == module ? 0.3 : 0), lineWidth: 0.6) }
                }
                .buttonStyle(.plain)
                .help(module.title(l10n.language))
                .accessibilityLabel(module.title(l10n.language))
                .accessibilityAddTraits(service.selected == module ? .isSelected : [])
                }
            }
        }
        .padding(4)
        .modifier(NotchControlSurface(cornerRadius: 13))
    }

    @ViewBuilder private var content: some View {
        if service.showingAppPanel {
            MenuPanelView(notchSize: service.contentSize)
        } else if let metric = service.selectedMetric {
            MetricDetailView(kind: metric)
        } else if service.modules.isEmpty {
            NotchEmptyView(symbol: "slider.horizontal.3", message: text.empty)
        } else {
            switch service.selected {
            case .controls: NotchControlsView(service: service)
            case .mixer: MixerSection(collapsible: false)
            case .music: NotchMusicView(compact: service.geometry.usesCompactContent)
            case .clipboard: NotchClipboardView(service: service)
            case .captures:
                if let capture = service.captureContent {
                    capture.frame(maxWidth: .infinity)
                } else {
                    RecentCapturesView(onClose: nil, notchHeight: service.contentSize.height)
                }
            case .files: NotchFilesView(service: service)
            case .system: NotchSystemView(select: service.showMetric)
            case .tools: QuickLauncherView(notchSize: service.contentSize)
            }
        }
    }
}

struct NotchShape: Shape {
    var attached: Bool
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard attached else { return Path(roundedRect: rect, cornerRadius: radius) }
        let shoulder: CGFloat = 8
        let bottom = min(radius, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.width - shoulder, y: shoulder),
                          control: CGPoint(x: rect.width - shoulder, y: 0))
        path.addLine(to: CGPoint(x: rect.width - shoulder, y: rect.height - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.width - shoulder - bottom, y: rect.height),
                          control: CGPoint(x: rect.width - shoulder, y: rect.height))
        path.addLine(to: CGPoint(x: shoulder + bottom, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: shoulder, y: rect.height - bottom),
                          control: CGPoint(x: shoulder, y: rect.height))
        path.addLine(to: CGPoint(x: shoulder, y: shoulder))
        path.addQuadCurve(to: .zero, control: CGPoint(x: shoulder, y: 0))
        path.closeSubpath()
        return path
    }
}

struct NotchNoticeView: View {
    let notice: NotchNotice
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: notice.symbol)
                .font(.system(size: 23, weight: .medium))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(notice.title).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(notice.detail).monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium))
                if let level = notice.level {
                    ProgressView(value: min(1, max(0, level)))
                        .progressViewStyle(.linear)
                        .tint(.white)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(height: 40)
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
        .accessibilityElement(children: .combine)
    }
}

struct NotchIconButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct NotchEmptyView: View {
    let symbol: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light))
            Text(message).font(.system(size: 12)).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

extension NotchModule: PanelOrderItem {
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .controls: return FeatureStrings.notch(language).controls
        case .mixer: return L10n.shared.s.mixerSection
        case .music: return FeatureStrings.radialMenu(language).mediaNowPlaying
        case .clipboard: return FeatureStrings.clipboard(language).title
        case .captures: return FeatureStrings.recentCaptures(language).title
        case .files: return FeatureStrings.notch(language).files
        case .system: return FeatureStrings.notch(language).system
        case .tools: return FeatureStrings.notch(language).tools
        }
    }
}

/// The hardware silhouette is always opaque black. Glass is confined to
/// control edges above that base, so activation or light mode cannot wash it out.
struct NotchControlSurface: ViewModifier {
    let cornerRadius: CGFloat
    var selected = false
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var glass = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
#if compiler(>=6.2)
            if #available(macOS 26, *), glass, !reduceTransparency {
                content.background(.black, in: shape)
                    .glassEffect(.clear.tint(.black).interactive(), in: shape)
            } else { content.background(.black, in: shape) }
#else
            content.background(.black, in: shape)
#endif
        }
        .overlay { shape.stroke(.white.opacity(selected ? 0.3 : 0.1), lineWidth: 0.6) }
    }
}
