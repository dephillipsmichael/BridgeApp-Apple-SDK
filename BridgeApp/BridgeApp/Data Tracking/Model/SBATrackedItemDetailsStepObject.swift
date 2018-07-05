//
//  SBATrackedItemDetailsStepObject.swift
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

/// `SBATrackedItemDetailsStepObject` is a concrete implementation of the `SBATrackedItemDetailsStep`
/// protocol that includes a template for creating multiple schedules assigned to this tracked item details.
///
/// - seealso: `SBAMedicationTrackingStepNavigator`
open class SBATrackedItemDetailsStepObject : RSDFormUIStepObject, SBATrackedItemDetailsStep {

    private enum FieldIdentifiers : String, CodingKey {
        case timeOfDay, daysOfWeek
    }
    
    /// The tracked item for this step.
    public private(set) var trackedItem: SBATrackedItem?
    
    public private(set) var previousAnswer: SBATrackedItemAnswer?
    /// The previous answer needs to be updated if a user goes to the step for a second time after filling in details
    public func updatePreviousAnswer(answer: SBATrackedItemAnswer?) {
        self.previousAnswer = answer
    }

    /// The template input field for selecting the time of day for a given schedule.
    lazy public private(set) var scheduleTimeTemplate: RSDCopyInputField = {
        return type(of: self).buildScheduleTimeInputField()
    }()
    
    /// The template input field for selecting the days of the week for a given schedule.
    lazy public private(set) var scheduleDaysTemplate: RSDCopyInputField = {
        return type(of: self).buildScheduleDaysInputField()
    }()
    
    /// Default initializer.
    /// - parameter identifier: The step identifier.
    public init(identifier: String) {
        let inputFields = type(of: self).buildInputFields()
        super.init(identifier: identifier, inputFields: inputFields, type: nil)
        _commonInit()
    }
    
    /// Initializer required for copying the step.
    public required init(identifier: String, type: RSDStepType?) {
        super.init(identifier: identifier, type: type ?? .form)
        _commonInit()
    }
    
    /// Initializer required for decoding the step.
    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        _commonInit()
    }
    
    private func _commonInit() {
        // Add the customization of the add more and go forward buttons.
        if self.actions?[.addMore] == nil {
            let addMoreAction = RSDUIActionObject(buttonTitle: Localization.localizedString("ADD_ANOTHER_SCHEDULE_BUTTON"))
            self.actions = [.addMore : addMoreAction]
        }
    }
    
    /// Override copy into to copy the schedule templates.
    open override func copyInto(_ copy: RSDUIStepObject) {
        super.copyInto(copy)
        guard let subclassCopy = copy as? SBATrackedItemDetailsStepObject else {
            assertionFailure("Superclass implementation of the `copy(with:)` protocol should return an instance of this class.")
            return
        }
        subclassCopy.scheduleTimeTemplate = self.scheduleTimeTemplate
        subclassCopy.scheduleDaysTemplate = self.scheduleDaysTemplate
    }
    
    /// Create a copy of this tracked item.
    open func copy(from trackedItem: SBATrackedItem, with previousAnswer: SBATrackedItemAnswer?) -> RSDStep? {
        let copy = self.copy(with: trackedItem.identifier)
        copy.trackedItem = trackedItem
        copy.previousAnswer = previousAnswer
        copy.title = self.title ?? trackedItem.title
        return copy
    }
    
    /// Subclasses must implement and *DO NOT* call super.
    open func answer(from taskResult: RSDTaskResult) -> SBATrackedItemAnswer? {
        // TODO: syoung 02/28/2018 Use `Decodable` protocol to create the appropriate item from a dictionary.
        fatalError("Subclasses must override this method to return a details answer that is appropriate to this step.")
    }

    /// Class function for returning the identifiers for the added fields.
    open class func inputFieldIdentifiers() -> [String] {
        return self.buildInputFields().map { $0.identifier }
    }
    
    /// Class function for building the input fields that should be included in a top section.
    open class func buildInputFields() -> [RSDInputField] {
        return []
    }
    
    /// Class function for building the input field for the schedule time.
    open class func buildScheduleTimeInputField() -> RSDCopyInputField {
        let timeField = RSDInputFieldObject(identifier: FieldIdentifiers.timeOfDay.stringValue, dataType: .base(.date), uiHint: .picker, prompt: Localization.localizedString("SCHEDULE_TIME_PROMPT"))
        timeField.range = RSDDateRangeObject(minuteInterval: nil, defaultTime: "08:00")
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        timeField.formatter = formatter
        return timeField
    }
    
    /// Class function for building the input field for the schedule days of the week.
    open class func buildScheduleDaysInputField() -> RSDCopyInputField {
        let daysField = RSDChoiceInputFieldObject(identifier: FieldIdentifiers.daysOfWeek.stringValue, choices: RSDWeekday.all.sorted(), dataType: .collection(.multipleChoice, .integer), uiHint: .list)
        daysField.formatter = RSDWeeklyScheduleFormatter()
        let popoverField = RSDPopoverInputFieldObject(inputField: daysField)
        popoverField.inputPrompt = Localization.localizedString("SCHEDULE_DAYS_PROMPT")
        popoverField.detail = Localization.localizedString("SCHEDULE_DAYS_OF_WEEK_DETAIL")
        let goForwardAction = RSDUIActionObject(buttonTitle: Localization.localizedString("BUTTON_SAVE"))
        popoverField.actions = [.navigation(.goForward) : goForwardAction]
        return popoverField
    }
}
