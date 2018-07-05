//
//  SBAMedicationTrackingStepNavigator.swift
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

open class SBAMedicationTrackingStepNavigator : SBATrackedItemsStepNavigator {
    
    override open class func decodeItems(from decoder: Decoder) throws -> (items: [SBATrackedItem], sections: [SBATrackedSection]?) {
        let container = try decoder.container(keyedBy: ItemsCodingKeys.self)
        let items = try container.decode([SBAMedicationItem].self, forKey: .items)
        let sections = try container.decodeIfPresent([SBATrackedSectionObject].self, forKey: .sections)
        return (items, sections)
    }
    
    override open class func buildSelectionStep(items: [SBATrackedItem], sections: [SBATrackedSection]?) -> SBATrackedItemsStep {
        let stepId = StepIdentifiers.selection.stringValue
        let step = SBATrackedSelectionStepObject(identifier: stepId, items: items, sections: sections)
        step.title = Localization.localizedString("MEDICATION_SELECTION_TITLE")
        step.detail = Localization.localizedString("MEDICATION_SELECTION_DETAIL")
        return step
    }
    
    override open class func buildReviewStep(items: [SBATrackedItem], sections: [SBATrackedSection]?) -> SBATrackedItemsStep? {
        let stepId = StepIdentifiers.review.stringValue
        let step = SBATrackedMedicationReviewStepObject(identifier: stepId, items: items, sections: sections, type: .review)

        // Set the default values for the title and subtitle to display depending upon state.
        step.addDetailsTitle = Localization.localizedString("MEDICATION_ADD_DETAILS_TITLE")
        step.addDetailsSubtitle = Localization.localizedString("MEDICATION_ADD_DETAILS_DETAIL")
        step.reviewTitle = Localization.localizedString("MEDICATION_REVIEW_TITLE")
        // Add the customization of the add more and go forward buttons.
        let addMoreAction = RSDUIActionObject(buttonTitle: Localization.localizedString("MEDICATION_EDIT_LIST_TITLE"))
        let goForwardAction = RSDUIActionObject(buttonTitle: Localization.localizedString("BUTTON_SAVE"))
        step.actions = [.navigation(.goForward) : goForwardAction,
                        .addMore : addMoreAction]
        
        return step
    }
    
    override open class func buildDetailSteps(items: [SBATrackedItem], sections: [SBATrackedSection]?) -> [SBATrackedItemDetailsStep]? {
        let detailStepObject = SBATrackedMedicationDetailStepObject(identifier: SBATrackedItemsStepNavigator.StepIdentifiers.addDetails.stringValue, type: .medicationDetails)
        return [detailStepObject]
    }
    
    override open class func buildLoggingStep(items: [SBATrackedItem], sections: [SBATrackedSection]?) -> SBATrackedItemsStep {
        return SBAMedicationLoggingStepObject(identifier: StepIdentifiers.logging.stringValue, items: items, sections: sections)
    }
    
    override open func instantiateLoggingResult() -> SBATrackedItemsCollectionResult {
        return SBAMedicationTrackingResult(identifier: self.reviewStep!.identifier)
    }
    
    override open func getDetailStep(with identifier: String) -> (RSDStep, SBATrackedItemAnswer)? {
        let returnValue = super.getDetailStep(with: identifier)
        if let detailStep = returnValue?.0 as? SBATrackedMedicationDetailStepObject {
            // Because we can visit a details step multiple times, we need to make sure
            // the previous answer is up to date for the step
            detailStep.updatePreviousAnswer(answer: returnValue?.1)
            detailStep.title = returnValue?.1.identifier
        }
        return returnValue
    }
    
    override open func step(after step: RSDStep?, with result: inout RSDTaskResult) -> (step: RSDStep?, direction: RSDStepDirection) {
        
        guard let _ = step?.identifier else {
            // TODO: mdephillips 7/3/18 remove this conditional once logging step is complete
            return (getSelectionStep(), .forward)
        }
        
        // Check if it is a detail step, if so, reverse to the review step
        if isDetailStep(with: step?.identifier) {
            var nextStep: RSDStep?
            if let _ = result.stepHistory.last as? SBARemoveMedicationResultObject {
                // Result of the step is to remove the medication
                let selectedIdentifiers = (result.findResult(for: self.selectionStep) as? SBATrackedItemsResult)?.selectedIdentifiers.filter({ $0 != step?.identifier })
                updateSelectedInMemoryResult(to: selectedIdentifiers, with: self.items)
                if selectedIdentifiers?.count == 0 {
                    // If there are no more selected medications, go back to selection step
                    nextStep = getSelectionStep()
                } else {
                    nextStep = getReviewStep()
                }
            } else {
                // When moving forward, always update the in-memory result before continuing.
                updateInMemoryResult(from: result, using: step)
                nextStep = getReviewStep()
            }
            return (nextStep, .reverse)
        }
        
        if let reviewStep = step as? SBATrackedItemsReviewStepObject,
            reviewStep.nextStepIdentifier == nil {            
            // TODO: mdephillips 7/3/18 move to reminders screen, for now end
            return (nil, .forward)
        }
        
        return super.step(after: step, with: &result)
    }
    
    func isDetailStep(with identifier: String?) -> Bool {
        guard let identifierUnwrapped = identifier else { return false }
        return self.items.contains(where: { $0.identifier == identifierUnwrapped })
    }
}

/// A medication item includes details for displaying a given medication.
public protocol SBAMedication : SBATrackedItem {
    
    /// Is the medication delivered via continuous injection? If this is the case, then questions about
    /// schedule timing and dosage should be skipped. Assumed `false` if `nil`.
    var isContinuousInjection: Bool? { get }
}

extension SBAMedication {
    
    /// The step identifier for mapping the results of a `RSDMedicationDetailsStepObject`.
    public var addDetailsIdentifier: String? {
        return (self.isContinuousInjection ?? false) ? nil : SBATrackedItemsStepNavigator.StepIdentifiers.addDetails.stringValue
    }
}

/// A medication item includes details for displaying a given medication.
///
/// - example:
/// ```
///    let json = """
///            {
///                "identifier": "advil",
///                "sectionIdentifier": "pain",
///                "title": "Advil",
///                "shortText": "Ibu",
///                "detail": "(Ibuprofen)",
///                "isExclusive": true,
///                "icon": "pill",
///                "injection": true
///            }
///            """.data(using: .utf8)! // our data in native (JSON) format
/// ```
public struct SBAMedicationItem : Codable, SBAMedication, RSDEmbeddedIconVendor {
    
    private enum CodingKeys : String, CodingKey {
        case identifier
        case sectionIdentifier
        case title
        case shortText
        case detail
        case _isExclusive = "isExclusive"
        case icon
        case isContinuousInjection = "injection"
    }
    
    /// A unique identifier that can be used to track the item.
    public let identifier: String
    
    /// An optional identifier that can be used to group the medication into a section.
    public let sectionIdentifier: String?

    /// Localized text to display as the full descriptor for the medication.
    public let title: String?
    
    /// Localized shortened text to display when used in a sentence.
    public let shortText: String?
    
    /// Detail text to display with additional information about the medication.
    public let detail: String?
    
    /// Whether or not the medication is set up so that *only* this can be selected
    /// for a given section.
    public var isExclusive: Bool {
        return _isExclusive ?? false
    }
    private let _isExclusive: Bool?
    
    /// An optional icon to display for the medication.
    public let icon: RSDImageWrapper?
    
    /// Is the medication delivered via continuous injection? If this is the case, then questions about
    /// schedule timing and dosage should be skipped.
    public let isContinuousInjection: Bool?
    
    public init(identifier: String, sectionIdentifier: String?, title: String? = nil, shortText: String? = nil, detail: String? = nil, icon: RSDImageWrapper? = nil, isExclusive: Bool = false, isContinuousInjection: Bool? = nil) {
        self.identifier = identifier
        self.sectionIdentifier = sectionIdentifier
        self.title = title
        self.shortText = shortText
        self.detail = detail
        self.icon = icon
        self._isExclusive = isExclusive
        self.isContinuousInjection = isContinuousInjection
    }
}

/// A medication answer for a given participant.
///
/// - example:
/// ```
///    let json = """
///            {
///                "identifier": "ibuprofen",
///                "dosage": "10/100 mg",
///                "scheduleItems" : [ { "daysOfWeek": [1,3,5], "timeOfDay" : "8:00" }]
///            }
///            """.data(using: .utf8)! // our data in native (JSON) format
///```
public struct SBAMedicationAnswer : Codable, SBATrackedItemAnswer {
    
    private enum CodingKeys : String, CodingKey {
        case identifier, dosage, scheduleItems, isContinuousInjection = "injection", timestamps
    }
    
    /// An identifier that maps to the associated `RSDMedicationItem`.
    public let identifier: String
    
    /// A string answer value for the dosage.
    public var dosage: String?
    
    /// The scheduled items associated with this medication result.
    public var scheduleItems: Set<RSDWeeklyScheduleObject>?
    
    /// Is the medication delivered via continuous injection? If this is the case, then questions about
    /// schedule timing and dosage should be skipped.
    public var isContinuousInjection: Bool?
    
    /// The timestamps to use to mark the medication as "taken".
    public var timestamps: [SBATimestamp]?
    
    /// Required items for a medication are dosage and schedule unless this is a continuous injection.
    public var hasRequiredValues: Bool {
        return (isContinuousInjection ?? false) || (dosage != nil && scheduleItems != nil)
    }
        
    /// Default initializer.
    /// - parameter identifier:
    public init(identifier: String) {
        self.identifier = identifier
    }
}

/// Extend the medication answer to allow for adding medication using an "Other" style field during
/// selection. All values defined in this section are `nil` or `false`.
extension SBAMedicationAnswer : SBAMedication {
    
    public var sectionIdentifier: String? {
        return nil
    }
    
    public var title: String? {
        return nil
    }
    
    public var detail: String? {
        return nil
    }
    
    public var shortText: String? {
        return nil
    }
    
    public var isExclusive: Bool {
        return false
    }
    
    public var imageVendor: RSDImageVendor? {
        return nil
    }
}

/// A medication tracking result which can be used to track the selected medications and details for each
/// medication.
public struct SBAMedicationTrackingResult : Codable, SBATrackedItemsCollectionResult {

    private enum CodingKeys : String, CodingKey {
        case identifier, type, startDate, endDate, medications = "items"
    }
    
    /// The identifier associated with the task, step, or asynchronous action.
    public let identifier: String
    
    /// A String that indicates the type of the result. This is used to decode the result using a `RSDFactory`.
    public private(set) var type: RSDResultType = .medication
    
    /// The start date timestamp for the result.
    public var startDate: Date = Date()
    
    /// The end date timestamp for the result.
    public var endDate: Date = Date()
    
    /// The list of medications that are currently selected.
    public var medications: [SBAMedicationAnswer] = []
    
    /// A list of the selected answer items.
    public var selectedAnswers: [SBATrackedItemAnswer] {
        return medications
    }
    
    public init(identifier: String) {
        self.identifier = identifier
    }
    
    public func copy(with identifier: String) -> SBAMedicationTrackingResult {
        var copy = SBAMedicationTrackingResult(identifier: identifier)
        copy.medications = self.medications
        return copy
    }
    
    mutating public func updateSelected(to selectedIdentifiers: [String]?, with items: [SBATrackedItem]) {
        guard let newIdentifiers = selectedIdentifiers, newIdentifiers.count > 0 else {
            self.medications = []
            return
        }
        
        func getMedication(with identifier: String) -> SBAMedicationAnswer {
            return medications.first(where: { $0.identifier == identifier }) ?? SBAMedicationAnswer(identifier: identifier)
        }

        // Filter and replace the meds.
        var allIdentifiers = newIdentifiers
        var meds = items.compactMap { (item) -> SBAMedicationAnswer? in
            guard allIdentifiers.contains(item.identifier) else { return nil }
            allIdentifiers.remove(where: { $0 == item.identifier })
            var medication = getMedication(with: item.identifier)
            medication.isContinuousInjection = (item as? SBAMedication)?.isContinuousInjection
            return medication
        }
        
        // For the medications that weren't in the items set, then just add using the identifier.
        meds.append(contentsOf: allIdentifiers.map { getMedication(with: $0) })
        
        // Set the new array
        self.medications = meds
    }
    
    mutating public func updateDetails(to newValue: SBATrackedItemAnswer) {
        if let newMedication = newValue as? SBAMedicationAnswer {
            guard let idx = medications.index(where: { $0.identifier == newValue.identifier }) else {
                return
            }
    
            // If this is a medication answer, then replace the existing one with a new one.
            var medication = newMedication
            if (newMedication.timestamps?.count ?? 0) == 0 {
                medication.timestamps = self.medications[idx].timestamps
            }
            self.medications.remove(at: idx)
            self.medications.insert(medication, at: idx)
        }
        else if let loggingResult = newValue as? SBATrackedLoggingResultObject,
            let itemIdentifier = loggingResult.itemIdentifier,
            let timingIdentifier = loggingResult.timingIdentifier {
            guard let idx = medications.index(where: { $0.identifier == itemIdentifier }) else {
                return
            }
            
            // If this is a timestamp logging then add/remove timestamp.
            var medication = self.medications[idx]
            var timestamps: [SBATimestamp] = medication.timestamps ?? []
            timestamps.remove(where: { $0.timingIdentifier == timingIdentifier })
            if let loggedDate = loggingResult.loggedDate {
                let newTimestamp = SBATimestamp(timingIdentifier: timingIdentifier, loggedDate: loggedDate)
                timestamps.append(newTimestamp)
            }
            medication.timestamps = timestamps
            self.medications.remove(at: idx)
            self.medications.insert(medication, at: idx)
        }
    }
    
    public func clientData() throws -> SBBJSONValue? {
        let dictionary = try self.rsd_jsonEncodedDictionary()
        return dictionary[CodingKeys.medications.stringValue] as? SBBJSONValue
    }
    
    /// Returns `true` to replace the results of a previous run.
    public func shouldReplacePreviousClientData() -> Bool {
        return true
    }
    
    mutating public func updateSelected(from clientData: SBBJSONValue, with items: [SBATrackedItem]) throws {
        let decoder = SBAFactory.shared.createJSONDecoder()
        let meds = try decoder.decode([SBAMedicationAnswer].self, from: clientData)
        self.medications = meds.map { (input) in
            var med = input
            med.timestamps = med.timestamps?.filter { Calendar.current.isDateInToday($0.loggedDate) }
            return med
        }
    }
}

/// A timestamp object is a light-weight Codable that can be used to record the timestamp for a logging event.
/// This object includes a `timingIdentifier` that maps to either an `SBATimeRange` or an
/// `RSDSchedule.timeOfDayString`.
public struct SBATimestamp : Codable, Hashable, RSDScheduleTime {
    private enum CodingKeys : String, CodingKey {
        case timingIdentifier = "timeOfDay", loggedDate
    }
    
    /// When the logged event is scheduled to occur.
    public let timingIdentifier: String
    
    /// The time/date for when the event was logged as *actually* occuring.
    public let loggedDate: Date
    
    public var hashValue: Int {
        return timingIdentifier.hashValue ^ loggedDate.hashValue
    }
    
    /// The time range for this timestamp.
    public var timeRange: SBATimeRange {
        return SBATimeRange(rawValue: timingIdentifier) ?? loggedDate.timeRange()
    }
    
    /// The time of day from the `RSDSchedule` that can be used to identify this schedule.
    public var timeOfDayString : String? {
        if SBATimeRange(rawValue: timingIdentifier) == nil {
            return timingIdentifier
        }
        else {
            return nil
        }
    }
}

