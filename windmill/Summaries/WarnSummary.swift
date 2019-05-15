//
//  WarnSummary.swift
//  windmill
//
//  Created by Markos Charatzas on 14/05/2019.
//  Copyright © 2019 qnoid.com. All rights reserved.
//

import Foundation

public struct WarnSummary {
    let error: Error
    
    /**
     Possible values as of Xcode 9.2
     
     "Swift Compiler Error"
     "Code Signing Error"
     "Dependency Analysis Error"
     
     */
    var issueType: String? {
        return error.localizedDescription
    }
    
    var message: String? {
        return (error as NSError).localizedFailureReason
    }
    
    var recoverySuggestion: String? {
        return (error as NSError).localizedRecoverySuggestion
    }

}