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
        LanguageOption(name: "英语", code: "en")
    ]
}

enum AppState: Equatable {
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
    @State private var progressText: String = ""
    @State private var selectedLanguage: LanguageOption = LanguageOption.options[0]
    @State private var currentTask: Task<Void, Never>? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            switch appState {
            case .initial:
                initialView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            case .fileSelected(let url):
                fileSelectedView(url: url)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .processing:
                processingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            case .completed(let url):
                completedView(url: url)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .saveSuccess:
                saveSuccessView()
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            case .error(let message):
                errorView(message: message)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 8)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appState)
        .tint(.accentColor)
    }
    
    // 初始化状态视图优化
    private func initialView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse.byLayer, options: .repeating)
            
            Text("选择视频文件")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            
            Text("支持 MP4、MOV、MKV、FLV 格式")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button("选择文件") {
                selectFile()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .focusable(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 已选择文件状态视图优化
    private func fileSelectedView(url: URL) -> some View {
        VStack(spacing: 20) {
            // 文件信息卡片
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "video.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 32, height: 32)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(url.lastPathComponent)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        
                        if let fileSize = getFileSize(url: url) {
                            Text("文件大小: \(fileSize)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.separator.opacity(0.5), lineWidth: 0.5)
                )
            }
            
            // 设置区域
            VStack(spacing: 16) {
                HStack {
                    Label("识别语言", systemImage: "globe")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Picker("语言", selection: $selectedLanguage) {
                        ForEach(LanguageOption.options) { option in
                            Text(option.name).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(minWidth: 100)
                }
                .padding(.horizontal, 4)
                
                Divider()
                
                // 操作按钮
                HStack(spacing: 12) {
                    Button("重新选择") {
                        selectFile()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    
                    Button("开始生成") {
                        appState = .processing(url)
                        currentTask = Task {
                            await processVideo(url: url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 获取文件大小的辅助函数
    private func getFileSize(url: URL) -> String? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = resourceValues.fileSize {
                return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
            }
        } catch {
            print("获取文件大小失败: \(error)")
        }
        return nil
    }
    
    // 处理中状态视图优化
    private func processingView() -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.blue)
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers)
                
                Text("正在处理视频")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            
            VStack(spacing: 16) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .scaleEffect(y: 1.5)
                    .padding(.horizontal, 8)
                
                HStack {
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    
                    Button("停止") {
                        currentTask?.cancel()
                        currentTask = nil
                        appState = .initial
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if !progressText.isEmpty {
                    Text(progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 已完成状态视图优化
    private func completedView(url: URL) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: appState)
                
                Text("字幕已生成")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            
            Button("保存字幕") {
                saveSubtitle(for: url)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 保存成功状态视图优化
    private func saveSuccessView() -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: appState)
                
                Text("保存成功")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text("字幕文件已保存到指定位置")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Button("继续处理下一个") {
                appState = .initial
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 错误状态视图优化
    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.orange)
                    .symbolEffect(.bounce, value: appState)
                
                Text("处理出错")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
            }
            
            Button("返回") {
                appState = .initial
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            // 检查任务是否已取消
            if Task.isCancelled {
                return
            }
            
            // 更新进度
            await updateProgress(0.1, "正在转换音频...")
            
            // 临时wav文件路径
            let tempDir = FileManager.default.temporaryDirectory
            let wavPath = tempDir.appendingPathComponent(
                url.deletingPathExtension().lastPathComponent + ".wav"
            )
            
            // 使用ffmpeg将视频转为wav
            try await convertVideoToWav(videoURL: url, outputURL: wavPath)
            
            // 检查任务是否已取消
            if Task.isCancelled {
                // 删除临时文件
                try? FileManager.default.removeItem(at: wavPath)
                return
            }
            
            await updateProgress(0.4, "正在识别语音...")
            
            // 使用WhisperKit进行语音识别
            let transcription = try await transcribeAudio(
                audioPath: wavPath.path
            )
            
            // 检查任务是否已取消
            if Task.isCancelled {
                // 删除临时文件
                try? FileManager.default.removeItem(at: wavPath)
                return
            }
            
            await updateProgress(0.8, "正在生成字幕...")
            
            // 将识别结果转为SRT格式
            self.subtitleContent = convertToSRT(transcription: transcription)
            
            await updateProgress(1.0, "完成")
            
            // 删除临时文件
            try FileManager.default.removeItem(at: wavPath)
            
            // 检查任务是否已取消
            if Task.isCancelled {
                return
            }
            
            // 更新状态
            await MainActor.run {
                appState = .completed(url)
            }
            
        } catch {
            // 如果不是因为取消导致的错误，才显示错误状态
            if !Task.isCancelled {
                await MainActor.run {
                    appState = .error("处理失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 更新进度
    private func updateProgress(_ value: Double, _ status: String = "") async {
        await MainActor.run {
            self.progress = value
            self.progressText = status
        }
    }
    
    // 使用ffmpeg将视频转为wav
    private func convertVideoToWav(videoURL: URL, outputURL: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
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
            WhisperKitConfig(model: "large-v3_947MB", computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndGPU), logLevel: Logging.LogLevel.debug)
        )
        var lng = selectedLanguage.code
        if lng == nil {
            lng = try await pipe.detectLanguage(audioPath: audioPath).language
        }
        print("语言: \(lng ?? "none")")
        let results = try await pipe.transcribe(
            audioPath: audioPath,
            decodeOptions: DecodingOptions(language: lng)
        ) { progress in
            Task {
                // 检查任务是否已取消
                if Task.isCancelled {
                    return
                }
                
                let cleanText = cleanTranscriptionText(progress.text)
                print("cleanText: \(cleanText)")
                await updateProgress(0.6, "生成中: \(cleanText)")
            }
            return !Task.isCancelled
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
    
    // 清洗识别文本，提取实际内容
    private func cleanTranscriptionText(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(
            of: #"<\|.*?\|>"#,
            with: "",
            options: .regularExpression
        )
        
        return cleaned
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
        let extractedText = cleanTranscriptionText(text)
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
        }
    }
}

#Preview {
    ContentView()
}
