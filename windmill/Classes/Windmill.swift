//
//  Windmill.swift
//  windmill
//
//  Created by Markos Charatzas on 13/03/2015.
//  Copyright (c) 2015 qnoid.com. All rights reserved.
//

import Foundation
import ObjectiveGit
import os


typealias WindmillProvider = () -> Windmill

/// domain is WindmillErrorDomain. code: WindmillErrorCode(s), has its userInfo set with NSLocalizedDescriptionKey, NSLocalizedFailureReasonErrorKey and NSUnderlyingErrorKey set

let WindmillErrorDomain : String = "io.windmill"
let XcodeBuildErrorDomain : String = "com.xcode.xcodebuild"

public struct WindmillStringKey : RawRepresentable, Equatable, Hashable {

    enum Test: String {
        case nothing
    }
    
    public static let test: WindmillStringKey = WindmillStringKey(rawValue: "io.windmill.windmill.key.test")!
    
    public static func ==(lhs: WindmillStringKey, rhs: WindmillStringKey) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
    
    public typealias RawValue = String
    
    public var hashValue: Int {
        return self.rawValue.hashValue
    }
    
    public var rawValue: String
    
    public init?(rawValue: String) {
        self.rawValue = rawValue
    }
}

/* final */ class Windmill: ProcessMonitor
{
    
    class func make(project: Project, user: String? = try? Keychain.defaultKeychain().findWindmillUser(), skipCheckout: Bool = false) -> (windmill: Windmill, chain: ProcessChain) {

        let windmill = Windmill(project: project)

        guard let user = user else {
            let repeatableExport = windmill.repeatableExport(skipCheckout: skipCheckout)
            return (windmill: windmill, chain: repeatableExport)
        }

        let repeatableDeploy = windmill.repeatableDeploy(user: user, skipCheckout: skipCheckout)
        return (windmill: windmill, chain: repeatableDeploy)
    }
    
    struct Notifications {
        static let willStartProject = Notification.Name("will.start")
        static let didBuildProject = Notification.Name("did.build")
        static let didTestProject = Notification.Name("did.test")
        static let didArchiveProject = Notification.Name("did.archive")
        static let didExportProject = Notification.Name("did.export")
        static let didDeployProject = Notification.Name("did.deploy")
        static let willMonitorProject = Notification.Name("will.monitor")
        
        static let activityDidLaunch = Notification.Name("activity.did.launch")
        static let activityDidExitSuccesfully = Notification.Name("activity.did.exit.succesfully")
        static let activityError = Notification.Name("activity.error")
    }
    
    let log = OSLog(subsystem: "io.windmill.windmill", category: "windmill")
    let notificationCenter = NotificationCenter.default
    
    let applicationCachesDirectory = Directory.Windmill.ApplicationCachesDirectory()
    let applicationSupportDirectory = Directory.Windmill.ApplicationSupportDirectory()

    lazy var projectHomeDirectory: ProjectHomeDirectory = FileManager.default.windmillHomeDirectory.projectHomeDirectory(at: project.name)
    lazy var projectSourceDirectory: ProjectSourceDirectory = applicationCachesDirectory.projectSourceDirectory(at: project.name)
    
    //
    var project: Project
    let processManager: ProcessManager
    
    var delegate: WindmillDelegate?
    

    // MARK: init
    
    public convenience init(project: Project) {
        self.init(processManager: ProcessManager(), project: project)
    }
    
    init(processManager: ProcessManager, project: Project) {

        self.project = project
        self.processManager = processManager
        self.processManager.monitor = self
    }
    
    private func build(project: Project, scheme: String, destination: Devices.Destination, wasSuccesful: ProcessWasSuccesful?) {
        
        self.build(project: project, scheme: scheme, destination: destination, repositoryLocalURL: projectSourceDirectory.URL, derivedDataURL: applicationCachesDirectory.derivedDataURL(at: project.name), resultBundle: applicationSupportDirectory.buildResultBundle(at: project.name), wasSuccesful: wasSuccesful)
    }
    
    private func didBuild(project: Project, using buildSettings: BuildSettings, appBundle: AppBundle, destination: Devices.Destination) {
        let directory = self.projectHomeDirectory

        let appBundleBuilt = appBundle
        let appBundle = directory.appBundle(name: project.name)
        try? FileManager.default.copyItem(at: appBundleBuilt.url, to: appBundle.url)
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Windmill.Notifications.didBuildProject, object: self, userInfo: ["project":project, "appBundle": appBundle, "destination": destination])
        }
        
    }
    
    private func didTest(project: Project, testsCount: Int, devices: Devices, destination: Devices.Destination, testableSummaries: [TestableSummary]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Windmill.Notifications.didTestProject, object: self, userInfo: ["project":project, "devices": devices, "destination": destination, "testsCount": testsCount, "testableSummaries": testableSummaries])
        }
        
    }
    
    private func didReadDevices(devices: Devices) {
        guard let destination = devices.destination else {
            os_log("Destination couldn't not be read from devices at '%{public}@'. Is a 'devices.json' present? Does it define a 'destination' dictionary?`", log: log, type: .debug, devices.url.path)
            return
        }
        Process.makeBoot(destination: destination).launch()
    }

    // MARK: private
    
    func buildChain(repositoryLocalURL: URL? = nil, derivedDataURL: URL, resultBundle: ResultBundle, buildWasSuccesful: ProcessWasSuccesful? = nil) -> ProcessChain {
        let directory = self.projectHomeDirectory
        let repositoryLocalURL = repositoryLocalURL ?? projectSourceDirectory.URL
        let configuration = directory.configuration()

        let readProjectConfiguration = Process.makeReadProjectConfiguration(repositoryLocalURL: repositoryLocalURL, projectConfiguration: configuration)
        return self.processManager.processChain(process: readProjectConfiguration, userInfo: ["activity": ActivityType.readProjectConfiguration, "configuration": configuration], wasSuccesful: ProcessWasSuccesful { [project = self.project, buildSettings = directory.buildSettings(), weak self] userInfo in
            
            let scheme = configuration.detectScheme(name: project.scheme)
            let readBuildSettings = Process.makeReadBuildSettings(repositoryLocalURL: repositoryLocalURL, scheme: scheme, buildSettings: buildSettings)
            self?.processManager.processChain(process: readBuildSettings, userInfo: ["activity" : ActivityType.showBuildSettings], wasSuccesful: ProcessWasSuccesful { [devices = directory.devices(), buildSettings = directory.buildSettings()] userInfo in
                let readDevices = Process.makeRead(devices: devices, for: buildSettings)
                self?.processManager.processChain(process: readDevices, userInfo: ["activity" : ActivityType.devices, "devices": devices], wasSuccesful: ProcessWasSuccesful { userInfo in
                    
                    self?.didReadDevices(devices: devices)
                    
                    let appBundle = directory.appBundle(name: project.name)
                    try? FileManager.default.removeItem(at: appBundle.url)
                    
                    guard let destination = devices.destination else {
                        if let log = self?.log {
                            os_log("Destination couldn't not be read from devices at '%{public}@'. Is a 'devices.json' present? Does it define a '' dictionary?`", log: log, type: .debug, devices.url.path)
                        }
                        return
                    }
                    
                    self?.build(project: project, scheme: scheme, destination: destination, repositoryLocalURL: repositoryLocalURL, derivedDataURL: derivedDataURL, resultBundle: resultBundle, wasSuccesful: buildWasSuccesful)
                }).launch()
            }).launch()
        })
    }
    
    /* private */ func exportChain(skipCheckout: Bool = false, exportWasSuccesful: ProcessWasSuccesful? = nil) -> ProcessChain {
        
        let directory = self.projectHomeDirectory
        let repositoryLocalURL = projectSourceDirectory.URL
        let checkout: Process = skipCheckout ? Process.makeSuccess() : Process.makeCheckout(sourceDirectory: projectSourceDirectory, project: self.project)        
        let derivedDataURL = applicationCachesDirectory.derivedDataURL(at: project.name)
        let applicationSupportDirectory = self.applicationSupportDirectory
        
        
        return self.processManager.processChain(process:checkout, userInfo: ["activity" : ActivityType.checkout, "repositoryLocalURL": repositoryLocalURL], wasSuccesful: ProcessWasSuccesful { [project = self.project, configuration = directory.configuration(), weak self] userInfo in
            let readProjectConfiguration = Process.makeReadProjectConfiguration(repositoryLocalURL: repositoryLocalURL, projectConfiguration: configuration)
            self?.processManager.processChain(process: readProjectConfiguration, userInfo: ["activity": ActivityType.readProjectConfiguration, "configuration": configuration], wasSuccesful: ProcessWasSuccesful { [buildSettings = directory.buildSettings()] userInfo in
                
                let scheme = configuration.detectScheme(name: project.scheme)
                let readBuildSettings = Process.makeReadBuildSettings(repositoryLocalURL: repositoryLocalURL, scheme: scheme, buildSettings: buildSettings)
                self?.processManager.processChain(process: readBuildSettings, userInfo: ["activity" : ActivityType.showBuildSettings], wasSuccesful: ProcessWasSuccesful { [devices = directory.devices(), buildSettings = directory.buildSettings()] userInfo in
                    let readDevices = Process.makeRead(devices: devices, for: buildSettings)
                    self?.processManager.processChain(process: readDevices, userInfo: ["activity" : ActivityType.devices, "devices": devices], wasSuccesful: ProcessWasSuccesful { userInfo in
                        
                        self?.didReadDevices(devices: devices)

                        let appBundle = directory.appBundle(name: project.name)
                        try? FileManager.default.removeItem(at: appBundle.url)
                        
                        guard let destination = devices.destination else {
                            if let log = self?.log {
                                os_log("Destination couldn't not be read from devices at '%{public}@'. Is a 'devices.json' present? Does it define a '' dictionary?`", log: log, type: .debug, devices.url.path)
                            }
                            return
                        }

                        self?.build(project: project, scheme: scheme, destination: destination, wasSuccesful: ProcessWasSuccesful { [destination = destination, devices = devices] buildInfo in

                            let appBundle = directory.appBundle(derivedDataURL: derivedDataURL, name: buildSettings.product.name ?? project.name)
                            self?.didBuild(project: project, using: buildSettings, appBundle: appBundle, destination: destination)

                            let test: Process
                            let userInfo: [AnyHashable: Any]
                            let testResultBundle = applicationSupportDirectory.testResultBundle(at: project.name)
                            
                            if WindmillStringKey.Test.nothing == (buildInfo?[WindmillStringKey.test] as? WindmillStringKey.Test) {
                                userInfo = ["activity" : ActivityType.test, "resultBundle": testResultBundle]
                                test = Process.makeSuccess()
                            } else {
                                userInfo = ["activity" : ActivityType.test, "artefact": ArtefactType.testReport, "devices": devices, "destination": destination, "resultBundle": testResultBundle]
                                test = Process.makeTestWithoutBuilding(repositoryLocalURL: repositoryLocalURL, project: project, scheme: scheme, destination: destination, derivedDataURL: derivedDataURL, resultBundle: testResultBundle)
                            }
                            
                            self?.processManager.processChain(process: test, userInfo: userInfo, wasSuccesful: ProcessWasSuccesful { userInfo in

                                if let testResultBundle = userInfo?["resultBundle"] as? ResultBundle, let testsCount = testResultBundle.info.testsCount, testsCount >= 0 {
                                    self?.didTest(project: project, testsCount: testsCount, devices: devices, destination: destination, testableSummaries: testResultBundle.testSummaries?.testableSummaries ?? [])
                                }

                                let archive: Archive = directory.archive(name: scheme)
                                let archiveResultBundle = applicationSupportDirectory.archiveResultBundle(at: project.name)
                                let makeArchive = Process.makeArchive(repositoryLocalURL: repositoryLocalURL, project: project, scheme: scheme, derivedDataURL: derivedDataURL, archive: archive, resultBundle: archiveResultBundle)
                                self?.processManager.processChain(process: makeArchive, userInfo: ["activity" : ActivityType.archive, "artefact": ArtefactType.archiveBundle, "archive": archive, "resultBundle": archiveResultBundle], wasSuccesful: ProcessWasSuccesful { userInfo in
                                    DispatchQueue.main.async {
                                        NotificationCenter.default.post(name: Windmill.Notifications.didArchiveProject, object: self, userInfo: ["project":project, "archive": archive])
                                    }
                                    
                                    let exportResultBundle = applicationSupportDirectory.exportResultBundle(at: project.name)
                                    let makeExport = Process.makeExport(repositoryLocalURL: repositoryLocalURL, archive: archive, exportDirectoryURL: directory.exportDirectoryURL(), resultBundle: exportResultBundle)
                                    
                                    let export = directory.export(name: scheme)
                                    
                                    self?.processManager.processChain(process: makeExport, userInfo: ["activity" : ActivityType.export, "artefact": ArtefactType.ipaFile, "export": export, "appBundle": appBundle, "resultBundle": exportResultBundle], wasSuccesful: ProcessWasSuccesful { userInfo in
                                        
                                        let appBundle = directory.appBundle(archive: archive, name: export.distributionSummary.name)
                                        
                                        let userInfo = userInfo?.merging(["project":project, "appBundle": appBundle], uniquingKeysWith: { (userInfo, _) -> Any in
                                            return userInfo
                                        })
                                        
                                        DispatchQueue.main.async {
                                            NotificationCenter.default.post(name: Windmill.Notifications.didExportProject, object: self, userInfo: userInfo)
                                        }
                                        
                                        exportWasSuccesful?.perform(userInfo: userInfo)
                                    }).launch()
                                }).launch()
                            }).launch()
                        })
                    }).launch()
                }).launch()
            }).launch()
        })
    }
    
    /* fileprivate */ func repeatableDeploy(user: String, skipCheckout: Bool = false) -> ProcessChain {

        let repositoryLocalURL = self.projectSourceDirectory.URL
        let buildSettings = self.projectHomeDirectory.buildSettings()
        
        let exportWasSuccesful = ProcessWasSuccesful { [project = self.project, pollDirectoryURL = self.projectHomeDirectory.pollURL(), weak self] userInfo in

            guard let export = userInfo?["export"] as? Export else {
                return
            }

            let deploy = Process.makeDeploy(repositoryLocalURL: repositoryLocalURL, export: export, forUser: user)
            self?.processManager.processChain(process: deploy, userInfo: ["activity" : ActivityType.deploy, "artefact": ArtefactType.otaDistribution], wasSuccesful: ProcessWasSuccesful { userInfo in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Windmill.Notifications.didDeployProject, object: self, userInfo: ["project":project, "buildSettings":buildSettings, "export": export])
                }
                
                #if DEBUG
                    let delayInSeconds:Int = 5
                #else
                    let delayInSeconds:Int = 30
                #endif
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Windmill.Notifications.willMonitorProject, object: self, userInfo: ["project":project])
                }

                if let log = self?.log {
                    os_log("will start monitoring", log: log, type: .debug)
                }

                self?.processManager.repeat(process: Process.makePoll(repositoryLocalURL: repositoryLocalURL, pollDirectoryURL: pollDirectoryURL), every: .seconds(delayInSeconds), until: 1, then: DispatchWorkItem {
                    self?.notificationCenter.post(name: Windmill.Notifications.willStartProject, object: self, userInfo: ["project":project])
                    self?.repeatableDeploy(user: user).launch()
                })
            }).launch()
        }
        
        return self.exportChain(skipCheckout: skipCheckout, exportWasSuccesful: exportWasSuccesful)
    }
    
    /* fileprivate */ func repeatableExport(skipCheckout: Bool = false) -> ProcessChain {

        let repositoryLocalURL = self.projectSourceDirectory.URL
        
        let exportWasSuccesful = ProcessWasSuccesful { [project = self.project, pollDirectoryURL = self.projectHomeDirectory.pollURL(), weak self] userInfo in
            
            #if DEBUG
                let delayInSeconds:Int = 5
            #else
                let delayInSeconds:Int = 30
            #endif

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Windmill.Notifications.willMonitorProject, object: self, userInfo: ["project":project])
            }

            if let log = self?.log {
                os_log("will start monitoring", log: log, type: .debug)
            }

            self?.processManager.repeat(process: Process.makePoll(repositoryLocalURL: repositoryLocalURL, pollDirectoryURL: pollDirectoryURL), every: .seconds(delayInSeconds), until: 1, then: DispatchWorkItem {
                self?.notificationCenter.post(name: Windmill.Notifications.willStartProject, object: self, userInfo: ["project":project])
                self?.repeatableExport().launch()
            })
        }
        
        return self.exportChain(skipCheckout: skipCheckout, exportWasSuccesful: exportWasSuccesful)
    }
    
    /* fileprivate */ func build(project: Project, scheme: String, destination: Devices.Destination, repositoryLocalURL: URL, derivedDataURL: URL, resultBundle: ResultBundle, wasSuccesful: ProcessWasSuccesful?) {
        
        let buildForTesting = Process.makeBuildForTesting(repositoryLocalURL: repositoryLocalURL, project:project, scheme: scheme, destination: destination, derivedDataURL: derivedDataURL, resultBundle: resultBundle)
        
        self.processManager.processChain(process: buildForTesting, userInfo: ["activity" : ActivityType.build, "resultBundle": resultBundle, "artefact": ArtefactType.appBundle], wasSuccesful: wasSuccesful).launch(recover: RecoverableProcess.recover(terminationStatus: 66) { [applicationSupportDirectory = self.applicationSupportDirectory, project = self.project, weak self] process in
            
            let resultBundle = applicationSupportDirectory.buildResultBundle(at: project.name)
            let build = Process.makeBuild(repositoryLocalURL: repositoryLocalURL, project:project, scheme: scheme, destination: destination, derivedDataURL: derivedDataURL, resultBundle: resultBundle)
            self?.processManager.processChain(process: build, userInfo: ["activity" : ActivityType.build, "resultBundle": resultBundle, "artefact": ArtefactType.appBundle, WindmillStringKey.test: WindmillStringKey.Test.nothing], wasSuccesful: wasSuccesful).launch()
        })
    }
    
    func removeDerivedData() -> Bool {
        return self.applicationCachesDirectory.removeDerivedData(at: project.name)
    }
    
    // MARK: public
    
    func run(process chain: ProcessChain)
    {
        self.notificationCenter.post(name: Windmill.Notifications.willStartProject, object: self, userInfo: ["project":project])
        
        chain.launch()
    }
    
    // MARK: ProcessMonitor
    func willLaunch(manager: ProcessManager, process: Process, userInfo: [AnyHashable : Any]?) {

    }
    
    func didLaunch(manager: ProcessManager, process: Process, userInfo: [AnyHashable : Any]?) {
        
        guard let activity = userInfo?["activity"] as? ActivityType else {
            return
        }
        
        os_log("activity did launch `%{public}@`", log: log, type: .debug, activity.rawValue)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notifications.activityDidLaunch, object: self, userInfo: userInfo)
        }
    }
    
    func didExit(manager: ProcessManager, process: Process, isSuccess: Bool, canRecover: Bool, userInfo: [AnyHashable : Any]?) {
        
        guard !canRecover else {
            os_log("will attempt to recover process '%{public}@'", log: log, type: .debug, process.executableURL?.lastPathComponent ?? "")
            return
        }
        
        guard let activity = userInfo?["activity"] as? ActivityType else {
            return
        }

        guard !isSuccess else {
            os_log("activity did exit success `%{public}@`", log: log, type: .debug, activity.rawValue)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notifications.activityDidExitSuccesfully, object: self, userInfo: userInfo)
            }
            return
        }
        
        let error: NSError = NSError.errorTermination(process: process, for: activity, status: process.terminationStatus)
        
        os_log("activity '%{public}@' did error: %{public}@", log: log, type: .error, error)
        
        switch activity {
        case .build, .test, .archive, .export:

            guard let resultBundle = userInfo?["resultBundle"] as? ResultBundle else {
                os_log("No 'resultBundle' was passed for activity: `%{public}@`. Have you set it in the userInfo?", log: log, type: .debug, activity.rawValue)
                return
            }
            
            if  resultBundle.info.errorCount > 0 {
                DispatchQueue.main.async { [info = resultBundle.info, errorCount = resultBundle.info.errorCount] in
                    
                    let error = NSError.activityError(underlyingError: error, for: activity, status: process.terminationStatus, info: info)
                    
                    NotificationCenter.default.post(name: Notifications.activityError, object: self, userInfo: userInfo?.merging(["error": error, "activity": activity, "errorCount":errorCount, "errorSummaries": info.errorSummaries], uniquingKeysWith: { (userInfo, _) -> Any in
                        return userInfo
                    }))
                }
            }
            if let testsFailedCount = resultBundle.info.testsFailedCount, testsFailedCount > 0 {
                DispatchQueue.main.async { [info = resultBundle.info] in
                    let error = NSError.testError(underlyingError: error, status: process.terminationStatus, info: info)

                    NotificationCenter.default.post(name: Notifications.activityError, object: self, userInfo: userInfo?.merging(["error": error, "activity": activity, "testsFailedCount":testsFailedCount, "testFailureSummaries": info.testFailureSummaries, "testableSummaries": resultBundle.testSummaries?.testableSummaries ?? []], uniquingKeysWith: { (userInfo, _) -> Any in
                        return userInfo
                    }))
                }
            }
        default:
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notifications.activityError, object: self, userInfo: userInfo?.merging(["error": error, "activity": activity], uniquingKeysWith:  { (userInfo, _) -> Any in
                    return userInfo
                }))
            }
        }
        return
    }
}
