import SwiftUI
import DueCore

/// Renders a drawing's elements into a SwiftUI Canvas. Shared by the inline note block,
/// the canvas editor, and PNG export, so a scene always looks the same everywhere.
/// Plot and scatter elements render into one shared graph layer (common axes and scale);
/// everything else draws in canvas coordinates on top.
struct DrawingSceneCanvas: View {
    let elements: [DrawingElement]
    /// Extra ink not yet committed (the stroke or shape being dragged right now).
    var previewElements: [DrawingElement] = []
    var highlightedID: UUID?

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Drawing.width, size.height / Drawing.height)
            drawGraphLayer(context: &context, size: size, scale: scale)
            for element in elements where element.kind != .plot && element.kind != .scatter {
                draw(element, context: &context, scale: scale, highlighted: element.id == highlightedID)
            }
            for element in previewElements {
                draw(element, context: &context, scale: scale, highlighted: false)
            }
        }
    }

    // MARK: - Elements

    private func draw(_ e: DrawingElement, context: inout GraphicsContext, scale: CGFloat, highlighted: Bool) {
        let color = Theme.color(e.color)
        let lineWidth = max(1.2, (e.size > 0 ? e.size : 2.5) * scale * 0.8)
        switch e.kind {
        case .stroke:
            guard e.points.count > 1 else { return }
            var path = Path()
            path.move(to: point(e.points[0], scale))
            for p in e.points.dropFirst() { path.addLine(to: point(p, scale)) }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        case .rect, .ellipse:
            let frame = CGRect(x: e.x * scale, y: e.y * scale, width: e.w * scale, height: e.h * scale)
            let path = e.kind == .rect
                ? Path(roundedRect: frame, cornerRadius: 8 * scale)
                : Path(ellipseIn: frame)
            context.fill(path, with: .color(color.opacity(0.10)))
            context.stroke(path, with: .color(color.opacity(highlighted ? 1 : 0.85)), lineWidth: highlighted ? 2.5 : 1.6)
            if !e.text.isEmpty {
                context.draw(
                    Text(e.text).font(.system(size: max(11, 15 * scale), weight: .medium)).foregroundStyle(color),
                    at: CGPoint(x: frame.midX, y: frame.midY)
                )
            }
        case .arrow:
            let a = point(e.from, scale), b = point(e.to, scale)
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: highlighted ? 3 : 1.8, lineCap: .round))
            context.fill(arrowHead(from: a, to: b), with: .color(color))
            if !e.text.isEmpty {
                context.draw(
                    Text(e.text).font(.system(size: max(10, 13 * scale))).foregroundStyle(color),
                    at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 12 * scale)
                )
            }
        case .text:
            context.draw(
                Text(e.text).font(.system(size: max(10, e.size * scale))).foregroundStyle(color.opacity(highlighted ? 1 : 0.95)),
                at: CGPoint(x: e.x * scale, y: e.y * scale),
                anchor: .topLeading
            )
        case .plot, .scatter:
            break // handled by the graph layer
        }
    }

    private func point(_ p: DrawingPoint, _ scale: CGFloat) -> CGPoint {
        CGPoint(x: p.x * scale, y: p.y * scale)
    }

    private func arrowHead(from a: CGPoint, to b: CGPoint) -> Path {
        let angle = atan2(b.y - a.y, b.x - a.x)
        let length: CGFloat = 11
        var path = Path()
        path.move(to: b)
        path.addLine(to: CGPoint(x: b.x - length * cos(angle - 0.45), y: b.y - length * sin(angle - 0.45)))
        path.addLine(to: CGPoint(x: b.x - length * cos(angle + 0.45), y: b.y - length * sin(angle + 0.45)))
        path.closeSubpath()
        return path
    }

    // MARK: - Graph layer

    private struct GraphSpace {
        let xRange: ClosedRange<Double>
        let yRange: ClosedRange<Double>
        let area: CGRect

        func place(_ x: Double, _ y: Double) -> CGPoint {
            let nx = (x - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound)
            let ny = (y - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound)
            return CGPoint(x: area.minX + nx * area.width, y: area.maxY - ny * area.height)
        }
    }

    private func drawGraphLayer(context: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        let graphs = elements.filter { $0.kind == .plot || $0.kind == .scatter }
        guard !graphs.isEmpty, let space = graphSpace(graphs, size: size, scale: scale) else { return }

        drawAxes(space, context: &context, scale: scale)

        for e in graphs {
            let color = Theme.color(e.color)
            if e.kind == .scatter {
                for p in e.points {
                    let c = space.place(p.x, p.y)
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(color))
                }
            } else if let f = PlotFunction.parse(e.expression) {
                var path = Path()
                var penDown = false
                let samples = 220
                for i in 0...samples {
                    let x = e.xMin + (e.xMax - e.xMin) * Double(i) / Double(samples)
                    guard let y = f.evaluate(at: x), space.yRange.contains(y) || abs(y) < 1e6 else {
                        penDown = false
                        continue
                    }
                    let p = space.place(x, min(max(y, space.yRange.lowerBound), space.yRange.upperBound))
                    if penDown {
                        path.addLine(to: p)
                    } else {
                        path.move(to: p)
                        penDown = true
                    }
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// Shared ranges across every graph element, padded, with degenerate spans widened.
    private func graphSpace(_ graphs: [DrawingElement], size: CGSize, scale: CGFloat) -> GraphSpace? {
        var xs: [Double] = []
        var ys: [Double] = []
        for e in graphs {
            if e.kind == .scatter {
                xs.append(contentsOf: e.points.map(\.x))
                ys.append(contentsOf: e.points.map(\.y))
            } else if let f = PlotFunction.parse(e.expression) {
                xs.append(e.xMin)
                xs.append(e.xMax)
                for i in 0...100 {
                    let x = e.xMin + (e.xMax - e.xMin) * Double(i) / 100
                    if let y = f.evaluate(at: x), abs(y) < 1e6 { ys.append(y) }
                }
            }
        }
        guard var minX = xs.min(), var maxX = xs.max(), var minY = ys.min(), var maxY = ys.max() else { return nil }
        if maxX - minX < 1e-9 { minX -= 1; maxX += 1 }
        if maxY - minY < 1e-9 { minY -= 1; maxY += 1 }
        let padY = (maxY - minY) * 0.08
        let inset = 34 * scale
        let area = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
        guard area.width > 20, area.height > 20 else { return nil }
        return GraphSpace(xRange: minX...maxX, yRange: (minY - padY)...(maxY + padY), area: area)
    }

    private func drawAxes(_ space: GraphSpace, context: inout GraphicsContext, scale: CGFloat) {
        let axisColor = Color.secondary.opacity(0.55)
        var axes = Path()
        // The x axis sits at y=0 when 0 is in range, else along the bottom; same for y.
        let xAxisY = space.yRange.contains(0) ? space.place(0, 0).y : space.area.maxY
        let yAxisX = space.xRange.contains(0) ? space.place(0, 0).x : space.area.minX
        axes.move(to: CGPoint(x: space.area.minX, y: xAxisY))
        axes.addLine(to: CGPoint(x: space.area.maxX, y: xAxisY))
        axes.move(to: CGPoint(x: yAxisX, y: space.area.minY))
        axes.addLine(to: CGPoint(x: yAxisX, y: space.area.maxY))
        context.stroke(axes, with: .color(axisColor), lineWidth: 1)

        let labelFont = Font.system(size: max(9, 10.5 * scale))
        context.draw(Text(short(space.xRange.lowerBound)).font(labelFont).foregroundStyle(axisColor),
                     at: CGPoint(x: space.area.minX, y: xAxisY + 11), anchor: .top)
        context.draw(Text(short(space.xRange.upperBound)).font(labelFont).foregroundStyle(axisColor),
                     at: CGPoint(x: space.area.maxX, y: xAxisY + 11), anchor: .top)
        context.draw(Text(short(space.yRange.upperBound)).font(labelFont).foregroundStyle(axisColor),
                     at: CGPoint(x: yAxisX - 6, y: space.area.minY), anchor: .trailing)
        context.draw(Text(short(space.yRange.lowerBound)).font(labelFont).foregroundStyle(axisColor),
                     at: CGPoint(x: yAxisX - 6, y: space.area.maxY), anchor: .trailing)
    }

    private func short(_ v: Double) -> String {
        abs(v - v.rounded()) < 0.005 ? String(Int(v.rounded())) : String(format: "%.2f", v)
    }
}

/// A drawing as it appears inline in the formatted note view.
struct DrawingBlockView: View {
    let drawing: Drawing

    var body: some View {
        ZStack {
            if drawing.isEmpty {
                Text("Empty drawing. Click to start.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                DrawingSceneCanvas(elements: drawing.elements)
            }
        }
        .aspectRatio(Drawing.width / Drawing.height, contentMode: .fit)
        .frame(maxWidth: 560)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: Theme.rowCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .accessibilityLabel(drawing.isEmpty ? "Empty drawing" : "Drawing with \(drawing.elements.count) elements")
    }
}
