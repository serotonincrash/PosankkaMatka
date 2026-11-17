//
//  RailGutter.swift
//  PosankkaMatka
//

import SwiftUI
import PosankkaCore

/// One row's slice of the stop rail. Each row draws the second half of the
/// segment into its stop and the first half of the segment out of it, so the
/// line runs continuously through rows of any height.
struct RailSlice: Equatable {
    enum Dot: Equatable { case passed, ahead, terminus }

    /// Travelled share (0...1) of the half-segment above the dot; nil for the first stop.
    var above: Double?
    /// Travelled share of the half-segment below; nil for the last stop.
    var below: Double?
    var dot: Dot
    /// The bus marker's height in the row (0 top ... 1 bottom), if it's in this row.
    var bus: Double?

    /// Slices for every call. A segment's travelled share is 1 into a passed
    /// stop, the bus's progress into the current one, 0 beyond.
    static func slices(for journey: VehicleJourney, allPassed: Bool = false) -> [RailSlice] {
        let calls = journey.calls
        func travelled(into index: Int) -> Double {
            if allPassed { return 1 }
            switch calls[index].state {
            case .passed: return 1
            case .current(let progress): return progress
            case .upcoming: return 0
            }
        }
        var slices = calls.indices.map { index -> RailSlice in
            let isLast = index == calls.count - 1
            let passed = allPassed || calls[index].state == .passed
            return RailSlice(
                above: index > 0 ? clamp((travelled(into: index) - 0.5) * 2) : nil,
                below: isLast ? nil : clamp(travelled(into: index + 1) * 2),
                dot: passed ? .passed : (isLast ? .terminus : .ahead),
                bus: nil
            )
        }
        guard !allPassed, let current = journey.nextStopIndex,
              case .current(let progress) = calls[current].state else { return slices }
        if current == 0 {
            // No segment above the first stop: approach within its top half.
            slices[0].bus = progress * 0.5
        } else if progress >= 0.5 {
            slices[current].bus = (progress - 0.5)
        } else {
            slices[current - 1].bus = 0.5 + progress
        }
        return slices
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

struct RailGutter: View {
    let slice: RailSlice
    let color: Color
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 28

    private let lineWidth: CGFloat = 4
    private var travelledColor: Color { Color.secondary.opacity(0.35) }

    var body: some View {
        Canvas { context, size in
            let x = size.width / 2
            let mid = size.height / 2
            if let above = slice.above {
                stroke(&context, x: x, from: 0, to: mid, travelled: above)
            }
            if let below = slice.below {
                stroke(&context, x: x, from: mid, to: size.height, travelled: below)
            }
            drawDot(&context, center: CGPoint(x: x, y: mid))
            if let bus = slice.bus {
                let center = CGPoint(x: x, y: size.height * bus)
                let rect = CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)
                context.fill(Path(ellipseIn: rect), with: .color(color))
                context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2.5)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    /// The first `travelled` share from `from` is grey, the rest route colour.
    private func stroke(_ context: inout GraphicsContext, x: CGFloat, from: CGFloat, to: CGFloat, travelled: Double) {
        let split = from + (to - from) * travelled
        if split > from {
            context.stroke(line(x, from, split), with: .color(travelledColor), lineWidth: lineWidth)
        }
        if split < to {
            context.stroke(line(x, split, to), with: .color(color), lineWidth: lineWidth)
        }
    }

    private func line(_ x: CGFloat, _ y1: CGFloat, _ y2: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: x, y: y1))
            path.addLine(to: CGPoint(x: x, y: y2))
        }
    }

    private func drawDot(_ context: inout GraphicsContext, center: CGPoint) {
        switch slice.dot {
        case .passed:
            let rect = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: rect), with: .color(travelledColor))
        case .ahead:
            let rect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: rect), with: .color(.white))
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 3)
        case .terminus:
            let rect = CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color))
            context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(.white), lineWidth: 2)
        }
    }
}
