//
//  WindmillTest.swift
//  windmillTests
//
//  Created by Markos Charatzas on 30/06/2017.
//  Copyright © 2017 qnoid.com. All rights reserved.
//

import XCTest

@testable import Windmill

class WindmillMock: Windmill {
    
    let expectation: XCTestExpectation
    
    init(expectation: XCTestExpectation, project: Project) {
        self.expectation = expectation
        super.init(processManager: ProcessManager(), project: project)
    }
    
    override func didExit(manager: ProcessManager, process: Process, isSuccess: Bool, canRecover: Bool, userInfo: [AnyHashable : Any]?) {
        XCTAssertFalse(isSuccess)
        XCTAssertEqual(process.terminationStatus, 128)
        expectation.fulfill()
    }
}

struct MetadataMock: Metadata {
    var url: URL
    
    var dictionary: [String : Any]?
}

class WindmillTest: XCTestCase {

    let bundle = Bundle(for: SequenceTest.self)
    
    override func setUp() {
        continueAfterFailure = false
    }
    
    func testGivenProjectWithNoTestTargetAssertExitAfterRecover() {
        
        let expectation = XCTestExpectation(description: #function)
        
        let name = "helloword-no-test-target"
        let repositoryLocalURL = bundle.url(forResource: name, withExtension: "")!
        
        let devices = Devices(metadata: MetadataJSONEncoded(url: bundle.url(forResource: "/metadata/\(name)/devices", withExtension: "json")!))
        
        let project = Project(name: name, scheme: name, origin: "any")
        let windmill = Windmill(project: project)
        
        NotificationCenter.default.addObserver(forName: Windmill.Notifications.activityDidExitSuccesfully, object: windmill, queue: OperationQueue.main) { notification in
            expectation.fulfill()
        }
        
        windmill.build(scheme: project.scheme, devices: devices, repositoryLocalURL: repositoryLocalURL, derivedDataURL: FileManager.default.trashDirectoryURL, resultBundle: windmill.applicationSupportDirectory.buildResultBundle(at: project.name), wasSuccesful: ProcessWasSuccesful.ok)
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testGivenProjectWithTestTargetAssertExitSuccesfully() {
        
        let expectation = XCTestExpectation(description: #function)
        
        let name = "project-with-unit-tests"
        let repositoryLocalURL = bundle.url(forResource: name, withExtension: "")!
        
        let devices = Devices(metadata: MetadataJSONEncoded(url: bundle.url(forResource: "/metadata/\(name)/devices", withExtension: "json")!))
        
        let project = Project(name: name, scheme: name, origin: "any")
        let windmill = Windmill(project: project)
        
        NotificationCenter.default.addObserver(forName: Windmill.Notifications.activityDidExitSuccesfully, object: windmill, queue: OperationQueue.main) { notification in
            expectation.fulfill()
        }
        
        windmill.build(scheme: project.scheme, devices: devices, repositoryLocalURL: repositoryLocalURL, derivedDataURL: FileManager.default.trashDirectoryURL, resultBundle: windmill.applicationSupportDirectory.buildResultBundle(at: project.name), wasSuccesful: ProcessWasSuccesful.ok)
        
        wait(for: [expectation], timeout: 30.0)
    }

    func testGivenProjectWithBuildErrorsAssertErrorSummary() {
        
        let expectation = XCTestExpectation(description: #function)
        
        let name = "project-with-build-errors"
        let repositoryLocalURL = bundle.url(forResource: name, withExtension: "")!
        
        let devices = Devices(metadata: MetadataJSONEncoded(url: bundle.url(forResource: "/metadata/\(name)/devices", withExtension: "json")!))
        
        let project = Project(name: name, scheme: name, origin: "any")
        let windmill = Windmill(project: project)
        
        NotificationCenter.default.addObserver(forName: Windmill.Notifications.activityError, object: windmill, queue: OperationQueue.main) { notification in
            let errorCount = notification.userInfo?["errorCount"] as? Int
            let errorSummaries = notification.userInfo?["errorSummaries"] as? [ResultBundle.ErrorSummary]
            
            XCTAssertEqual(5, errorCount)
            XCTAssertNotNil(errorSummaries)
            expectation.fulfill()
        }
        
        windmill.build(scheme: project.scheme, devices: devices, repositoryLocalURL: repositoryLocalURL, derivedDataURL: FileManager.default.trashDirectoryURL, resultBundle: windmill.applicationSupportDirectory.buildResultBundle(at: project.name), wasSuccesful: ProcessWasSuccesful.ok)
        
        wait(for: [expectation], timeout: 30.0)
    }


    func testGivenProjectWithoutTestTargetAssertTestWasSuccesful() {
        
        let expectation = XCTestExpectation(description: #function)
        let processManager = ProcessManager()
        var monitor: ProcessMonitor? = ProcessMonitorFailOnUnsuccessfulExit()
        processManager.monitor = monitor
        
        let name = "helloword-no-test-target"
        let repositoryLocalURL = bundle.url(forResource: name, withExtension: "")!
        
        let devices = Devices(metadata: MetadataJSONEncoded(url: bundle.url(forResource: "/metadata/\(name)/devices", withExtension: "json")!))
        let buildSettings = BuildSettings(metadata: MetadataJSONEncoded(url: bundle.url(forResource: "/metadata/\(name)/build/settings", withExtension: "json")!))
        
        let resultBundleURL = FileManager.default.trashDirectoryURL.appendingPathComponent("ResultBundle").appendingPathComponent(name).appendingPathComponent(CharacterSet.Windmill.random(characters: CharacterSet.lowercaseLetters, length: 16)).appendingPathComponent("\(name).bundle")
        let buildResultBundle = ResultBundle(url: resultBundleURL.appendingPathComponent("build").appendingPathComponent("\(name).bundle"), info: ResultBundle.Info.make(at: URL(string: "any")!))
        let testResultBundle = ResultBundle(url: resultBundleURL.appendingPathComponent("test").appendingPathComponent("\(name).bundle"), info: ResultBundle.Info.make(at: URL(string: "any")!))

        defer {
            try? FileManager.default.removeItem(at: buildResultBundle.url)
            try? FileManager.default.removeItem(at: testResultBundle.url)
            monitor = nil
        }
        
        let project = Project(name: name, scheme: "helloword-no-test-target", origin: "any")
        let windmill = Windmill(processManager: processManager, project: project)
        
        let readTestMetadata = Process.makeReadDevices(repositoryLocalURL: repositoryLocalURL, scheme: project.scheme, devices: devices, buildSettings: buildSettings)
        let testSkip = Process.makeTestSkip(repositoryLocalURL: repositoryLocalURL, scheme: project.scheme, devices: devices, derivedDataURL: FileManager.default.trashDirectoryURL, resultBundle: testResultBundle)
        
        windmill.build(scheme: project.scheme, devices: devices, repositoryLocalURL: repositoryLocalURL, derivedDataURL: FileManager.default.trashDirectoryURL, resultBundle: testResultBundle, wasSuccesful: ProcessWasSuccesful { _ in
            processManager.sequence(process: readTestMetadata, wasSuccesful: ProcessWasSuccesful { _ in
                processManager.sequence(process: testSkip, wasSuccesful: ProcessWasSuccesful { _ in
                    expectation.fulfill()
                }).launch()
            }).launch()
        })        
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testGivenProjectWithTestTargetAssertTestWasSuccesful() {
        
        let expectation = XCTestExpectation(description: #function)
        let processManager = ProcessManager()
        var monitor: ProcessMonitor? = ProcessMonitorFailOnUnsuccessfulExit()
        processManager.monitor = monitor
        
        let name = "helloworld"
        
        let repositoryLocalURL = bundle.url(forResource: name, withExtension: "")!
        
        let resultBundleURL = FileManager.default.trashDirectoryURL.appendingPathComponent("ResultBundle").appendingPathComponent(name).appendingPathComponent(CharacterSet.Windmill.random(characters: CharacterSet.lowercaseLetters, length: 16))
        let buildResultBundle = ResultBundle(url: resultBundleURL.appendingPathComponent("build").appendingPathComponent("\(name).bundle"), info: ResultBundle.Info.make(at: URL(string: "any")!))
        let testResultBundle = ResultBundle(url: resultBundleURL.appendingPathComponent("test").appendingPathComponent("\(name).bundle"), info: ResultBundle.Info.make(at: URL(string: "any")!))

        defer {
            try? FileManager.default.removeItem(at: buildResultBundle.url)
            try? FileManager.default.removeItem(at: testResultBundle.url)
            monitor = nil
        }
        
        let project = Project(name: name, scheme: "helloworld", origin: "any")
        let windmill = Windmill(processManager: processManager, project: project)

        let devices = Devices(metadata: MetadataJSONEncoded(url: bundle.url(forResource: "/metadata/\(name)/devices", withExtension: "json")!))
        let buildSettings = BuildSettings(metadata: MetadataJSONEncoded(url: bundle.url(forResource: "/metadata/\(name)/build/settings", withExtension: "json")!))
        
        let readTestMetadata = Process.makeReadDevices(repositoryLocalURL: repositoryLocalURL, scheme: project.scheme, devices: devices, buildSettings: buildSettings)
        let testWithoutBuilding = Process.makeTestWithoutBuilding(repositoryLocalURL: repositoryLocalURL, scheme: project.scheme, devices: devices, derivedDataURL: FileManager.default.trashDirectoryURL, resultBundle: testResultBundle)

        windmill.build(scheme: project.scheme, devices: devices, repositoryLocalURL: repositoryLocalURL, derivedDataURL: FileManager.default.trashDirectoryURL, resultBundle: buildResultBundle, wasSuccesful: ProcessWasSuccesful { _ in
            processManager.sequence(process: readTestMetadata, wasSuccesful: ProcessWasSuccesful { _ in
                processManager.sequence(process: testWithoutBuilding, wasSuccesful: ProcessWasSuccesful { _ in
                    expectation.fulfill()
                }).launch()
            }).launch()
        })

        wait(for: [expectation], timeout: 60.0)
    }
    
    func testGivenProjectWithoutAvailableSimulatorAssertTestWasSuccesful() {
        
        let expectation = XCTestExpectation(description: #function)
        let processManager = ProcessManager()
        var monitor: ProcessMonitor? = ProcessMonitorFailOnUnsuccessfulExit()
        processManager.monitor = monitor
        
        let name = "no_simulator_available"
        let repositoryLocalURL = bundle.url(forResource: name, withExtension: "")!
        
        let resultBundleURL = FileManager.default.trashDirectoryURL.appendingPathComponent("ResultBundle").appendingPathComponent(name).appendingPathComponent(CharacterSet.Windmill.random(characters: CharacterSet.lowercaseLetters, length: 16)).appendingPathComponent("\(name).bundle")
        let resultBundle = ResultBundle(url: resultBundleURL, info: ResultBundle.Info.make(at: URL(string: "any")!))
        
        defer {
            try? FileManager.default.removeItem(at: resultBundle.url)
            monitor = nil
        }
        
        let project = Project(name: name, scheme: "no_simulator_available", origin: "any")
        let windmill = Windmill(processManager: processManager, project: project)

        let devices = Devices(metadata: MetadataJSONEncoded(url: bundle.url(forResource: "/metadata/\(name)/devices", withExtension: "json")!))
        let buildSettings = BuildSettings(metadata: MetadataJSONEncoded(url: bundle.url(forResource: "/metadata/\(name)/build/settings", withExtension: "json")!))
        
        let readTestMetadata = Process.makeReadDevices(repositoryLocalURL: repositoryLocalURL, scheme: project.scheme, devices: devices, buildSettings: buildSettings)
        let test = Process.makeTestSkip(repositoryLocalURL: repositoryLocalURL, scheme: project.scheme, devices: devices, derivedDataURL: FileManager.default.trashDirectoryURL, resultBundle: resultBundle)
        
        windmill.build(scheme: project.scheme, devices: devices, repositoryLocalURL: repositoryLocalURL, derivedDataURL: FileManager.default.trashDirectoryURL, resultBundle: resultBundle, wasSuccesful: ProcessWasSuccesful { _ in
            processManager.sequence(process: readTestMetadata, wasSuccesful: ProcessWasSuccesful { _ in
                processManager.sequence(process: test, wasSuccesful: ProcessWasSuccesful { _ in
                    expectation.fulfill()
                }).launch()
            }).launch()
        })

        wait(for: [expectation], timeout: 30.0)
    }
    
    func testGivenErrorAssertDidExitCalled() {
        
        let repoName = "any"
        let project = Project(name: repoName, scheme: "any", origin: "invalid")

        let url = FileManager.default.trashDirectoryURL.appendingPathComponent(repoName)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: nil)
        let process = Process.makeCheckout(sourceDirectory: FileManager.default.directory(FileManager.default.trashDirectoryURL), project: project)
        
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let expectation = self.expectation(description: #function)
        
        let windmill = WindmillMock(expectation: expectation, project: project)
        
        let repeatableDeploy = windmill.repeatableDeploy(user: "user")
        windmill.run(sequence: repeatableDeploy)

        wait(for: [expectation], timeout: 5.0)
    }
}
