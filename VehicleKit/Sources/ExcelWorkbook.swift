import CoreXLSX
import Foundation

/// .xlsx 只读访问入口 —— M1 excelParser 的落点。
/// M0 仅打通 CoreXLSX 链接并暴露 Sheet 名清单，解析规则随后续里程碑逐条直译。
public enum ExcelWorkbook {
    /// 列出工作簿的全部 Sheet 页名称（按文件内顺序）
    public static func sheetNames(at url: URL) throws -> [String] {
        guard let file = XLSXFile(filepath: url.path) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSFilePathErrorKey: url.path,
            ])
        }
        guard let workbook = try file.parseWorkbooks().first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let sheets = try file.parseWorksheetPathsAndNames(workbook: workbook)
        return sheets.compactMap { $0.name }
    }
}
