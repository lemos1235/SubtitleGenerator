//
//  ContentView.swift
//  Subtitle Generator
//
//  Created by Alfred Jobs on 2025/5/9.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import WhisperKit
import Foundation

struct LanguageOption: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let code: String?
    
    static let options: [LanguageOption] = [
        LanguageOption(name: "自动", code: nil),
        LanguageOption(name: "中文", code: "zh"),
        LanguageOption(name: "日语", code: "ja"),
        LanguageOption(name: "英文", code: "en")
    ]
}

enum AppState {
    case initial
    case fileSelected(URL)
    case processing(URL)
    case completed(URL)
    case saveSuccess(URL)
    case error(String)
}

struct ContentView: View {
    @State private var appState: AppState = .initial
    @State private var subtitleContent: String = ""
    @State private var progress: Double = 0.0
    @State private var selectedLanguage: LanguageOption = LanguageOption.options[0]
    
    var body: some View {
        VStack(spacing: 20) {
            switch appState {
            case .initial:
                initialView()
            case .fileSelected(let url):
                fileSelectedView(url: url)
            case .processing:
                processingView()
            case .completed(let url):
                completedView(url: url)
            case .saveSuccess:
                saveSuccessView()
            case .error(let message):
                errorView(message: message)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
    
    // 初始化状态视图
    private func initialView() -> some View {
        Button("选择文件") {
            selectFile()
        }
    }
    
    // 已选择文件状态视图
    private func fileSelectedView(url: URL) -> some View {
        VStack(spacing: 20) {
            Text("已选择：\(url.lastPathComponent)")
                .lineLimit(1)
                .truncationMode(.middle)
            
            HStack(spacing: 6) {
                Button("重新选择") {
                    selectFile()
                }
                
                Picker("语言", selection: $selectedLanguage) {
                    ForEach(LanguageOption.options) { option in
                        Text(option.name).tag(option)
                    }
                }
                .frame(maxWidth: 70)
                .labelsHidden()
                
                Button("生成字幕") {
                    appState = .processing(url)
                    Task {
                        await processVideo(url: url)
                    }
                }
            }
        }
    }
    
    // 处理中状态视图
    private func processingView() -> some View {
        VStack {
            Text("正在处理视频..")
            ProgressView(value: progress, total: 1.0)
                .padding()
            Text(String(format: "%.1f%%", progress * 100))
        }
    }
    
    // 已完成状态视图
    private func completedView(url: URL) -> some View {
        VStack(spacing: 20) {
            Text("已完成")
            
            Button("保存字幕") {
                saveSubtitle(for: url)
            }
        }
    }
    
    // 保存成功状态视图
    private func saveSuccessView() -> some View {
        VStack(spacing: 20) {
            Text("保存成功")
            
            Button("下一个") {
                appState = .initial
            }
        }
    }
    
    // 错误状态视图
    private func errorView(message: String) -> some View {
        Text("出错了~\n\(message)")
            .multilineTextAlignment(.center)
    }
    
    // 选择文件
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType.mpeg4Movie,
            UTType.quickTimeMovie,
            UTType(filenameExtension: "mkv") ?? UTType.movie,
            UTType(filenameExtension: "flv") ?? UTType.movie
        ]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                DispatchQueue.main.async {
                    self.appState = .fileSelected(url)
                }
            } else if case .fileSelected = appState {
                // 如果取消且当前状态是fileSelected，保持不变
            } else {
                // 如果取消且不是fileSelected状态，回到初始状态
                DispatchQueue.main.async {
                    self.appState = .initial
                }
            }
        }
    }
    
    // 处理视频生成字幕
    private func processVideo(url: URL) async {
        do {
            // 更新进度
            await updateProgress(0.1, "正在转换音频...")
            
            // 临时wav文件路径
            let tempDir = FileManager.default.temporaryDirectory
            let wavPath = tempDir.appendingPathComponent(
                url.deletingPathExtension().lastPathComponent + ".wav"
            )
            
            // 使用ffmpeg将视频转为wav
            try await convertVideoToWav(videoURL: url, outputURL: wavPath)
            
            await updateProgress(0.4, "正在识别语音...")
            
            // 使用WhisperKit进行语音识别
            let transcription = try await transcribeAudio(
                audioPath: wavPath.path
            )
            
            await updateProgress(0.8, "正在生成字幕...")
            
            // 将识别结果转为SRT格式
            self.subtitleContent = convertToSRT(transcription: transcription)
            
            await updateProgress(1.0, "完成")
            
            // 删除临时文件
            try FileManager.default.removeItem(at: wavPath)
            
            // 更新状态
            await MainActor.run {
                appState = .completed(url)
            }
            
        } catch {
            await MainActor.run {
                appState = .error("处理失败: \(error.localizedDescription)")
            }
        }
    }
    
    // 更新进度
    private func updateProgress(_ value: Double, _ status: String = "") async {
        await MainActor.run {
            self.progress = value
        }
    }
    
    // 使用ffmpeg将视频转为wav
    private func convertVideoToWav(videoURL: URL, outputURL: URL) async throws {
        let process = Process()
        
        let bundleFfmpegURL = Bundle.main.url(
            forResource: "ffmpeg",
            withExtension: nil
        )!
        
        process.executableURL = bundleFfmpegURL
        process.arguments = [
            "-i", videoURL.path,
            "-vn", // 禁用视频
            "-acodec", "pcm_s16le", // 音频编码
            "-ar", "16000", // 采样率
            "-ac", "1", // 单声道
            "-y", // 覆盖现有文件
            outputURL.path
        ]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "FFMpegError",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "FFmpeg转换失败"]
            )
        }
    }
    
    // 设置文件可执行权限
    private func setExecutablePermission(for url: URL) throws {
        let attributes = [FileAttributeKey.posixPermissions: 0o755]
        try FileManager.default
            .setAttributes(attributes, ofItemAtPath: url.path)
    }
    
    // 使用WhisperKit进行语音识别
    private func transcribeAudio(audioPath: String) async throws -> TranscriptionResult {
        let pipe = try await WhisperKit(
            WhisperKitConfig(logLevel: Logging.LogLevel.debug)
        )
        let results = try await pipe.transcribe(
            audioPath: audioPath,
            decodeOptions: DecodingOptions(language: selectedLanguage.code)
        ) { progress in
            // 更新识别进度（从0.4到0.8）
            Task {
                await self.updateProgress(0.4 + 0.2)
            }
            return true // 继续处理
        }
        guard let transcription = results.first else {
            throw NSError(
                domain: "TranscriptionError",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "转录失败"]
            )
        }
        return transcription
    }
    
    // 工具：把秒数转成 "HH:MM:SS,mmm" 的 SRT 时间戳
    private func formatTime(_ seconds: Float) -> String {
        let totalMilliseconds = Int((seconds * 1000).rounded())
        let ms = totalMilliseconds % 1000
        let s = (totalMilliseconds / 1000) % 60
        let m = (totalMilliseconds / 60000) % 60
        let h = totalMilliseconds / 3600000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
    
    /// Format a time value as a string
    func formatTime(seconds: Float, alwaysIncludeHours: Bool, decimalMarker: String) -> String {
        let hrs = Int(seconds / 3600)
        let mins = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        let msec = Int((seconds - floor(seconds)) * 1000)
        
        if alwaysIncludeHours || hrs > 0 {
            return String(
                format: "%02d:%02d:%02d\(decimalMarker)%03d",
                hrs,
                mins,
                secs,
                msec
            )
        } else {
            return String(
                format: "%02d:%02d\(decimalMarker)%03d",
                mins,
                secs,
                msec
            )
        }
    }
    
    func formatSegment(index: Int, start: Float, end: Float, text: String) -> String {
        let startFormatted = formatTime(
            seconds: Float(start),
            alwaysIncludeHours: true,
            decimalMarker: ","
        )
        let endFormatted = formatTime(
            seconds: Float(end),
            alwaysIncludeHours: true,
            decimalMarker: ","
        )
        // 用正则提取文本内容
        let pattern = "<\\|\\d+\\.\\d+\\|>(.*?)<\\|\\d+\\.\\d+\\|>"
        var extractedText = ""
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(
            in: text,
            options: [],
            range: NSRange(text.startIndex..., in: text)
           ),
           let range = Range(match.range(at: 1), in: text) {
            extractedText = String(text[range])
        }
        return "\(index)\n\(startFormatted) --> \(endFormatted)\n\(extractedText)"
    }
    
    // 将识别结果转为 SRT 格式
    private func convertToSRT(transcription: TranscriptionResult) -> String {
        var srtLines: [String] = []
        var index = 1
        for segment in transcription.segments {
            if let wordTimings = segment.words, !wordTimings.isEmpty {
                for wordTiming in wordTimings {
                    let line = formatSegment(
                        index: index,
                        start: wordTiming.start,
                        end: wordTiming.end,
                        text: wordTiming.word
                    )
                    srtLines.append(line)
                    index += 1
                }
            } else {
                // Use segment timing if word timings are not available
                let line = formatSegment(
                    index: index,
                    start: segment.start,
                    end: segment.end,
                    text: segment.text
                )
                srtLines.append(line)
                index += 1
            }
        }
        
        // 3. 合并返回
        return srtLines.joined(separator: "\n\n")
    }
    
    // 保存字幕文件
    private func saveSubtitle(for videoURL: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = videoURL
            .deletingPathExtension()
            .appendingPathExtension("srt").lastPathComponent
        panel.allowedContentTypes = [UTType(
            filenameExtension: "srt"
        ) ?? UTType.text]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    // 将生成的字幕内容写入文件
                    try self.subtitleContent
                        .write(to: url, atomically: true, encoding: .utf8)
                    
                    DispatchQueue.main.async {
                        self.appState = .saveSuccess(videoURL)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.appState =
                            .error("保存失败: \(error.localizedDescription)")
                    }
                }
            }
            // 如果取消，保持在completed状态
        }
    }
}

#Preview {
    ContentView()
}
