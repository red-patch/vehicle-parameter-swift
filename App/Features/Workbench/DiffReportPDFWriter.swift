import AppKit
import CoreText
import Foundation

/// 参数对比报告 PDF 导出（CGContext + CoreText，矢量文字）
enum DiffReportPDFWriter {
    static func write(
        rows: [DiffRow],
        baseName: String,
        targetName: String,
        countsText: String,
        modeText: String,
        to url: URL
    ) throws {
        // A4 竖版（72dpi 点阵：595 × 842）
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 36
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 15, nil)
        let headerFont = CTFontCreateWithName("Helvetica" as CFString, 9, nil)
        let bodyFont = CTFontCreateWithName("PingFangSC" as CFString, 8.5, nil)
        let headerFontCT = CTFontCreateWithName("PingFangSC-Semibold" as CFString, 9, nil)

        let columns: [(title: String, x: CGFloat, width: CGFloat)] = [
            ("状态", margin, 34),
            ("分组", margin + 38, 88),
            ("参数名", margin + 130, 168),
            ("基准值", margin + 302, 100),
            ("对比值", margin + 406, 100),
            ("产品", margin + 510, pageWidth - margin * 2 - 510),
        ]

        var y: CGFloat = 0
        var pageNumber = 0

        func beginPage() {
            ctx.beginPDFPage(nil)
            pageNumber += 1
            y = pageHeight - margin
        }

        func drawText(_ text: String, x: CGFloat, y position: CGFloat, font: CTFont,
                      color: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1), width: CGFloat) {
            let attr = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: NSColor(cgColor: color) ?? .black,
            ])
            let line = CTLineCreateWithAttributedString(attr)
            // 单行截断（超宽尾部省略）
            guard let truncated = CTLineCreateTruncatedLine(line, Double(width), .end, nil) else { return }
            ctx.textPosition = CGPoint(x: x, y: position)
            CTLineDraw(truncated, ctx)
        }

        func stateColor(_ state: DiffRow.State) -> CGColor {
            switch state {
            case .added: CGColor(red: 0.0, green: 0.5, blue: 0.15, alpha: 1)
            case .removed: CGColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1)
            case .modified: CGColor(red: 0.8, green: 0.45, blue: 0.0, alpha: 1)
            case .unchanged: CGColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1)
            }
        }

        func drawHeader(pageIsFirst: Bool) {
            if pageIsFirst {
                drawText("参数对比报告", x: margin, y: y - 14, font: titleFont, width: 400)
                y -= 30
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                drawText("导出时间：\(formatter.string(from: Date()))    模式：\(modeText)",
                         x: margin, y: y, font: headerFont,
                         color: CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1), width: 500)
                y -= 12
                drawText("基准：\(baseName)", x: margin, y: y, font: headerFont,
                         color: CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1), width: 500)
                y -= 11
                drawText("对比：\(targetName)", x: margin, y: y, font: headerFont,
                         color: CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1), width: 500)
                y -= 13
                drawText(countsText, x: margin, y: y, font: headerFontCT, width: 500)
                y -= 8
            }
            // 列头
            ctx.setFillColor(CGColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1))
            ctx.fill(CGRect(x: margin, y: y - 13, width: pageWidth - margin * 2, height: 14))
            for column in columns {
                drawText(column.title, x: column.x, y: y - 10, font: headerFontCT, width: column.width)
            }
            y -= 18
        }

        beginPage()
        drawHeader(pageIsFirst: true)

        let rowHeight: CGFloat = 13.5
        for item in rows {
            if y - rowHeight < margin {
                // 页脚页码
                drawText("第 \(pageNumber) 页", x: pageWidth - margin - 40, y: margin - 14, font: headerFont,
                         color: CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1), width: 60)
                beginPage()
                drawHeader(pageIsFirst: false)
            }
            let baseline = y - rowHeight + 3
            drawText(item.state.rawValue, x: columns[0].x, y: baseline, font: bodyFont,
                     color: stateColor(item.state), width: columns[0].width)
            drawText(item.group, x: columns[1].x, y: baseline, font: bodyFont,
                     color: CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1), width: columns[1].width)
            drawText(item.name, x: columns[2].x, y: baseline, font: bodyFont, width: columns[2].width)
            drawText(item.oldValue, x: columns[3].x, y: baseline, font: bodyFont, width: columns[3].width)
            drawText(item.newValue, x: columns[4].x, y: baseline, font: bodyFont, width: columns[4].width)
            drawText(item.productName ?? "", x: columns[5].x, y: baseline, font: bodyFont,
                     color: CGColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1), width: columns[5].width)
            y -= rowHeight
        }
        drawText("第 \(pageNumber) 页", x: pageWidth - margin - 40, y: margin - 14, font: headerFont,
                 color: CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1), width: 60)
        ctx.endPDFPage()
    }
}
