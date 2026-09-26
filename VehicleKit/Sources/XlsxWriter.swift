import Foundation
import CoreXLSX

#if canImport(XlsxWriterShim)
import XlsxWriterShim

// MARK: - xlsx 写出（libxlsxwriter 封装）
//
// AGENTS.md 约定：libxlsxwriter 的 C 互操作集中在本文件，不在 Swift 代码里散写。
// 车上云模板格式与旧版对齐：sheet "产品准入导入模版"，AOA 字符串矩阵，列宽 wch 30/40。

public enum XlsxWriterError: Error, LocalizedError {
    case createFailed
    case writeFailed(String)
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .createFailed: "无法创建 xlsx 工作簿"
        case .writeFailed(let m): "写入失败：\(m)"
        case .saveFailed(let m): "保存失败：\(m)"
        }
    }
}

public enum XlsxWriter {
    /// 将二维字符串矩阵写为 xlsx（全字符串单元格，与旧版 Rust export_xlsx 的
    /// write_string 路径一致；colWidths 为 SheetJS wch 近似字符宽）
    public static func write(
        rows: [[String]],
        sheetName: String,
        colWidths: [Double],
        to url: URL
    ) throws {
        guard let workbook = workbook_new(url.path) else {
            throw XlsxWriterError.createFailed
        }
        // workbook_close() 内部会释放 workbook（官方用法只调 close 不再 free）；
        // 仅在 close 之前的错误路径需要手动 free，避免双重释放导致堆损坏
        do {
            guard let sheet = workbook_add_worksheet(workbook, sheetName) else {
                throw XlsxWriterError.createFailed
            }

            for (r, row) in rows.enumerated() {
                for (c, value) in row.enumerated() {
                    let error = worksheet_write_string(sheet, lxw_row_t(r), lxw_col_t(c), value, nil)
                    if error != LXW_NO_ERROR {
                        throw XlsxWriterError.writeFailed("r\(r)c\(c)")
                    }
                }
            }
            for (c, width) in colWidths.enumerated() {
                worksheet_set_column(sheet, lxw_col_t(c), lxw_col_t(c), width, nil)
            }

            if workbook_close(workbook) != LXW_NO_ERROR {
                throw XlsxWriterError.saveFailed(url.path)
            }
        } catch {
            lxw_workbook_free(workbook)
            throw error
        }
    }

    /// 车上云系统模板导出（文件名：车上云系统导入_{车型}_{yyyyMMdd}.xlsx）
    public static func writeVehicleCloudTemplate(
        items: [MatchItem], productName: String, to url: URL, date: Date = Date()
    ) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone.current
        let dateText = formatter.string(from: date)
        let suggested = "车上云系统导入_\(productName)_\(dateText).xlsx"
        // 文件名约定供 UI 侧默认名使用；写出本身以传入 url 为准
        _ = suggested

        try write(
            rows: SmartFiller.vehicleCloudRows(items),
            sheetName: "产品准入导入模版",
            colWidths: [30, 40],
            to: url
        )
    }
}

#endif
