//
//  ProcessTest.swift
//  windmillTests
//
//  Created by Markos Charatzas on 09/08/2017.
//  Copyright © 2017 qnoid.com. All rights reserved.
//

import XCTest

@testable import Windmill

class EphemeralFileManager: FileManager {
    
    let url: URL
    
    init(url: URL) {
        self.url = url

    }
    
    deinit {
        try? self.removeItem(at: url)
    }
}

class ProcessTest: XCTestCase {

    let bundle: Bundle = Bundle(for: ProcessTest.self)
    
    func testGivenProcessOutputAssertCallback() {
     
        let queue = DispatchQueue(label: "any")
        
        let process = Process()
        process.launchPath = "/bin/echo"
        process.arguments = ["Hello World"]
        let standardOutputPipe = Pipe()
        process.standardOutput = standardOutputPipe
        
        let expectation = self.expectation(description: #function)

        var actualAvailableString: String?
        var actualCount = 0
        let read = process.windmill_waitForDataInBackground(standardOutputPipe, queue: queue) { availableString, count in
            actualAvailableString = availableString
            actualCount = count
            expectation.fulfill()
        }

        read.activate()
        process.launch()

        queue.async {
            process.waitUntilExit()
        }

        self.waitForExpectations(timeout: 5.0, handler: nil)
        XCTAssertEqual(actualAvailableString, "Hello World\n")
        XCTAssertEqual(actualCount, "Hello World\n".count)
    }
    
    func testGivenUnicodeOutputAssertStringCount() {
        
        let queue = DispatchQueue(label: "any")

        let process = Process()
        process.launchPath = "/bin/echo"
        process.arguments = ["🥑"]
        let standardOutputPipe = Pipe()
        process.standardOutput = standardOutputPipe
        
        let expectation = self.expectation(description: #function)
        
        var actualAvailableString: String?
        var actualCount = 0
        let read = process.windmill_waitForDataInBackground(standardOutputPipe, queue: queue) { availableString, count in
            actualAvailableString = availableString
            actualCount = count
            expectation.fulfill()
        }

        read.activate()
        process.launch()

        queue.async {
            process.waitUntilExit()
        }
        
        self.waitForExpectations(timeout: 5.0, handler: nil)
        XCTAssertEqual(actualAvailableString, "🥑\n")
        XCTAssertEqual(actualCount, "🥑\n".utf8.count)
    }
    
    /**
     */
    func testGivenProjectAssertMakeTestConfigurationFileExists() {

        let buildSettingsMetadataURL = bundle.url(forResource: "ProcessTest/build/settings", withExtension: "json")!
        let buildSettings = BuildSettings(url: buildSettingsMetadataURL)
        let devicesMetadataURL = Bundle(for: ProcessTest.self).url(forResource: "ProcessTest/test/devices", withExtension: "json")!
        let devices = Devices(metadata: MetadataJSONEncoded(url: devicesMetadataURL))
        
        let process = Process.makeList(devices: devices, for: buildSettings.deployment)
        
        process.launch()
        process.waitUntilExit()
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: devices.url.path))
        
        XCTAssertGreaterThanOrEqual(devices.version!, 11.3)
        XCTAssertEqual(devices.platform, "iOS")
        XCTAssertEqual(devices.destination?.name, "iPhone 5s")
        XCTAssertEqual(devices.destination?.udid, "3FA86B8D-EF8A-4E7C-8C39-681E33A6E99F")
    }
    
    /**
     - Precondition: a checked out project
     */
    func testGivenProjectWithoutAvailableSimulatorAssertMakeTestConfigurationFileExists() {
        
        let buildSettingsMetadataURL = bundle.url(forResource: "ProcessTest/build/settings", withExtension: "json")!
        let buildSettings = BuildSettings(url: buildSettingsMetadataURL)
        let devicesMetadataURL = Bundle(for: ProcessTest.self).url(forResource: "ProcessTest/test/devices", withExtension: "json")!
        let devices = Devices(metadata: MetadataJSONEncoded(url: devicesMetadataURL))
        
        let process = Process.makeList(devices: devices, for: buildSettings.deployment)

        process.launch()
        process.waitUntilExit()
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: devices.url.path))
        

        XCTAssertGreaterThanOrEqual(devices.version!, 11.3)
        XCTAssertEqual(devices.platform, "iOS")
        XCTAssertEqual(devices.destination?.name, "iPhone 5s")
        XCTAssertEqual(devices.destination?.udid, "461A4D6E-7215-4665-80FD-48311E77297B")
    }    
}
