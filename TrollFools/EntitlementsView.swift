//
//  EntitlementsView.swift
//  TrollFools
//
//  Created by fzltfzlt on 2025/5/28.
//

import SwiftUI
import MachOKit
import CocoaLumberjackSwift

struct EntitlementsView: View {
    let app: App
    let injector: InjectorV3?
    
    @State var isImporterPresented = false
    @State var importResult: URL?
    @State var importContent: String?
    @State var mergedContent: String?
    
    init(_ app: App) {
        self.app = app
        self.injector = try? InjectorV3(app.url)
    }

    var body: some View {
        if let result = injector?.hasAlternate(app.url), result {
            restoreContent
        } else {
            injectContent
        }
    }
    
    var restoreContent: some View {
        VStack(spacing: 60) {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("App current entitlements", comment: ""))
                    .font(.body)
                
                ScrollView {
                    if let entitlements = app.entitlements {
                        Text(entitlements)
                            .font(.system(.footnote, design: .monospaced))
                            .padding(4)
                            .foregroundColor(.secondary)
                            .cornerRadius(6)
                    } else {
                        Text(NSLocalizedString("No entitlements found.", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minHeight: 70, maxHeight: 100)
                .background(Color(.secondarySystemBackground))
            }
            
            Spacer()
            
            NavigationLink {
                if let err = restoreEntitlements() {
                    Text("Failed!\(err)")
                } else {
                    Text("Success!")
                }
            } label: {
                Label(NSLocalizedString("Merge Entitlements", comment: ""),
                      systemImage: "syringe")
            }
        }
    }
    
    var injectContent: some View {
        VStack(spacing: 60) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text((importResult != nil) ? importResult!.lastPathComponent : "Import a entitlements")
                        .font(.body)
                    
                    Spacer()
                    
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label(NSLocalizedString("Import", comment: ""), systemImage: "square.and.arrow.down")
                    }
                }
                ScrollView {
                    Text(importContent ?? "Import a entitlement file")
                        .font(.system(.footnote, design: .monospaced))
                        .padding(4)
                        .cornerRadius(6)
                        .foregroundColor(importContent != nil ? .secondary : .red)
                }
                .frame(minHeight: 70, maxHeight: 100)
                .background(Color(.secondarySystemBackground))
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("App original entitlements", comment: ""))
                    .font(.body)
                
                ScrollView {
                    if let entitlements = app.entitlements {
                        Text(entitlements)
                            .font(.system(.footnote, design: .monospaced))
                            .padding(4)
                            .foregroundColor(.secondary)
                            .cornerRadius(6)
                    } else {
                        Text(NSLocalizedString("No entitlements found.", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minHeight: 70, maxHeight: 100)
                .background(Color(.secondarySystemBackground))
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("Preview merged entitlements", comment: ""))
                    .font(.body)
                
                ScrollView {
                    Text(mergedContent ?? "Unmerged yet.")
                        .font(.system(.footnote, design: .monospaced))
                        .padding(4)
                        .cornerRadius(6)
                        .foregroundColor(mergedContent != nil ? .primary : .red)
                }
                .frame(minHeight: 200, maxHeight: 300)
                .background(Color(.secondarySystemBackground))
            }
        
            Spacer()
            
            NavigationLink {
                let result = mergeAndInjectEntitlements()
                switch result {
                case .success(let url):
                    Text("Success!\(url?.absoluteString ?? "")")
                case .failure(let err):
                    Text("Failed!\(err)")
                }
            } label: {
                Label(NSLocalizedString("Merge Entitlements", comment: ""),
                      systemImage: "syringe")
            }
        }
        .padding()
        .navigationTitle(app.name)
        .onAppear(perform: {
            loadEntitlementsFromApp()
        })
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [
                .init(filenameExtension: "xml")!,
                .init(filenameExtension: "plist")!,
                .init(filenameExtension: "entitlements")!,
            ],
            allowsMultipleSelection: false
        ) {
            result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    self.importResult = url
                    do {
                        let data = try Data(contentsOf: url)
                        if let content = String(data: data, encoding: .utf8) {
                            self.importContent = content
                            self.updateMergedEntitlements()
                        }
                    } catch {
                        DDLogError("Failed to read file: \(error)", ddlog: InjectorV3.main.logger)
                    }
                }
            case .failure(let err):
                DDLogInfo("\(err)", ddlog: InjectorV3.main.logger)
            }
        }
    }
    
    fileprivate func updateMergedEntitlements() {
        mergedContent = nil
        if let importedEntitlements = importContent,
            let appEntitlements = app.entitlements,
            let importedData = importedEntitlements.data(using: .utf8),
            let appData = appEntitlements.data(using: .utf8),
            let importedPlist = try? PropertyListSerialization.propertyList(from: importedData, options: [], format: nil) as? [String: Any],
            let appPlist = try? PropertyListSerialization.propertyList(from: appData, options: [], format: nil) as? [String: Any] {
            // 合并字典，importedPlist 优先级高
            let merged = appPlist.merging(importedPlist) { _, new in new }
            
            // 转回 XML 字符串
            if let mergedData = try? PropertyListSerialization.data(fromPropertyList: merged, format: .xml, options: 0) {
                mergedContent = String(data: mergedData, encoding: .utf8) ?? ""
            }
        }
    }
    
    fileprivate func loadEntitlementsFromApp() {
        do {
            let injector = try InjectorV3(app.url)
            app.entitlements = try injector.cmdExportEntitlements(app.url)
            updateMergedEntitlements()
        } catch {
            DDLogError("\(error)", ddlog: InjectorV3.main.logger)
        }
    }
    
    fileprivate func mergeAndInjectEntitlements() -> Result<URL?, Error> {
        do {
            if let injector = self.injector {
                if injector.appID.isEmpty {
                    injector.appID = app.id
                }
                if injector.teamID.isEmpty {
                    injector.teamID = app.teamID
                }
            }
            if let mergedContent = mergedContent {
                try self.injector?.injectEntitlements(mergedContent)
                return .success(self.injector?.latestLogFileURL)
            } else {
                var userInfo: [String: Any] = [
                    NSLocalizedDescriptionKey: "unmerged yet",
                ]
                if let logFileURL = self.injector?.latestLogFileURL {
                    userInfo[NSURLErrorKey] = logFileURL
                }
                let nsErr = NSError(domain: gTrollFoolsErrorDomain, code: 0, userInfo: userInfo)
                return .failure(nsErr)
            }
        } catch {
            DDLogError("\(error)", ddlog: InjectorV3.main.logger)
            var userInfo: [String: Any] = [
                NSLocalizedDescriptionKey: error.localizedDescription,
            ]
            if let logFileURL = self.injector?.latestLogFileURL {
                userInfo[NSURLErrorKey] = logFileURL
            }
            let nsErr = NSError(domain: gTrollFoolsErrorDomain, code: 0, userInfo: userInfo)
            return .failure(nsErr)
        }
    }
    
    fileprivate func restoreEntitlements() -> Error? {
        do {
            if let executableURL = try self.injector?.locateExecutableInBundle(app.url) {
                try self.injector?.restoreAlternate(executableURL)
            }
            return nil
        } catch {
            DDLogError("\(error)", ddlog: InjectorV3.main.logger)
            var userInfo: [String: Any] = [
                NSLocalizedDescriptionKey: error.localizedDescription,
            ]
            if let logFileURL = self.injector?.latestLogFileURL {
                userInfo[NSURLErrorKey] = logFileURL
            }
            let nsErr = NSError(domain: gTrollFoolsErrorDomain, code: 0, userInfo: userInfo)
            return nsErr
        }
    }
}


struct EntitlementsView_Previews: PreviewProvider {
    static var previews: some View {
        EntitlementsView(App.example)
    }
}

extension App {
    static var example: App {
        let app = App(
            id: "123",
            name: "SampleApp",
            type: "",
            teamID: "",
            url: URL("https://xxx.com")!
        )
        app.entitlements = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>com.apple.security.application-groups</key>
                <array>
                    <string>group.com.example.app</string>
                </array>
            </dict>
            </plist>
            """
        return app
    }
}
