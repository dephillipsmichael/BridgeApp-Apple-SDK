//
//  SBAFactory.swift
//  BridgeApp
//
//  Copyright © 2018 Sage Bionetworks. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// 1.  Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2.  Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// 3.  Neither the name of the copyright holder(s) nor the names of any contributors
// may be used to endorse or promote products derived from this software without
// specific prior written permission. No license is granted to the trademarks of
// the copyright holders even if such marks are included in this software.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import Foundation

extension RSDStepNavigatorType {
    
    /// Defaults to creating a `SBAMedicationTrackingStepNavigator`.
    public static let medicationTracking: RSDStepNavigatorType = "medicationTracking"
    
    /// Defaults to creating a `SBATrackedItemsStepNavigator`.
    public static let tracking: RSDStepNavigatorType = "tracking"
}

extension RSDStepType {
    
    /// Defaults to creating a `SBATrackedItemsLoggingStepObject`.
    public static let logging: RSDStepType = "logging"
    
    /// Defaults to creating a `SBATrackedItemsReviewStepObject`.
    public static let review: RSDStepType = "review"
    
    /// Defaults to creating a `SBATrackedSelectionStepObject`.
    public static let selection: RSDStepType = "selection"
    
    /// Defaults to creating a `SBASymptomLoggingStepObject`.
    public static let symptomLogging: RSDStepType = "symptomLogging"
    
    /// Defaults to creating a 'SBATrackedMedicationDetailStepObject'
    public static let medicationDetails: RSDStepType = "medicationDetails"
}

open class SBAFactory : RSDFactory {
    
    public var configuration : SBABridgeConfiguration {
        return SBABridgeConfiguration.shared
    }
    
    /// Override to implement custom step navigators.
    override open func decodeStepNavigator(from decoder: Decoder, with type: RSDStepNavigatorType) throws -> RSDStepNavigator {
        switch type {
        case .medicationTracking:
            return try SBAMedicationTrackingStepNavigator(from: decoder)
        case .tracking:
            return try SBATrackedItemsStepNavigator(from: decoder)
        default:
            return try super.decodeStepNavigator(from: decoder, with: type)
        }
    }
    
    /// Override to implement custom step types.
    override open func decodeStep(from decoder:Decoder, with type:RSDStepType) throws -> RSDStep? {
        switch (type) {
        case .selection:
            return try SBATrackedSelectionStepObject(from: decoder)
        case .logging:
            return try SBATrackedItemsLoggingStepObject(from: decoder)
        case .symptomLogging:
            return try SBASymptomLoggingStepObject(from: decoder)
        case .medicationDetails:
            return try SBATrackedMedicationDetailStepObject(from: decoder)
        case .taskInfo:
            if let taskInfo = try? SBAActivityInfoObject(from: decoder),
                let transformer = self.configuration.instantiateTaskTransformer(for: taskInfo) {
                return RSDTaskInfoStepObject(with: taskInfo, taskTransformer: transformer)
            }
            else {
                return try super.decodeStep(from: decoder, with: type)
            }
        default:
            return try super.decodeStep(from: decoder, with: type)
        }
    }
}
