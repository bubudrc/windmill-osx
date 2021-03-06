//
//  ProjectTest.swift
//  windmill
//
//  Created by Markos Charatzas (markos@qnoid.com) on 12/03/2015.
//  Copyright (c) 2015 qnoid.com. All rights reserved.
//

import Cocoa
import XCTest
@testable import Windmill

class ProjectTest: XCTestCase {
    
    func testEquatable()
    {
        let sameName = "name"
        let x = Project(isWorkspace: false, name: sameName, scheme: "scheme", origin: "x")
        
        XCTAssertTrue(x == x, "`x == x` should be `true`")
        
        let y = Project(isWorkspace: false, name: sameName, scheme: "scheme", origin: "x")
        
        XCTAssertTrue(x == y, "`x == y` implies `y == x`")
        XCTAssertTrue(y == x, "`x == y` implies `y == x`")
        
        let z = Project(isWorkspace: false, name: sameName, scheme: "scheme", origin: "x")
        
        XCTAssertTrue(y == z, "`x == y` and `y == z` implies `x == z`")
        XCTAssertTrue(x == z, "`x == y` and `y == z` implies `x == z`")
    }
    
    func testNonEquatable()
    {
        let this = Project(isWorkspace: false, name: "this", scheme: "scheme", origin: "foo")
        let that = Project(isWorkspace: false, name: "that", scheme: "scheme", origin: "foo")
        
        XCTAssertFalse(this == that, "Projects without the same origin should not be equal.")
    }
    
    func testHashable()
    {
        let sameOrigin = "origin"
        let this = Project(isWorkspace: false, name: "foo", scheme: "scheme", origin: sameOrigin)
        let that = Project(isWorkspace: false, name: "foo", scheme: "scheme", origin: sameOrigin)
        
        var set : Set<Project> = []
        set.insert(this)
        set.insert(that)
        
        XCTAssertEqual(1, set.count, "Set should only have one project of the same origin.")
    }
    
    func testNonHashable()
    {
        let this = Project(isWorkspace: false, name: "this", scheme: "scheme", origin: "foo")
        let that = Project(isWorkspace: false, name: "that", scheme: "scheme", origin: "foo")
        
        var set : Set<Project> = []
        set.insert(this)
        set.insert(that)
        
        XCTAssertEqual(2, set.count, "Set should have two projects of different origin.")
    }
}


