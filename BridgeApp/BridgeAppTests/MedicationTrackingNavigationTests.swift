//
//  MedicationTrackingTests.swift
//  BridgeAppTests
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

import XCTest
@testable import BridgeApp

class MedicationTrackingNavigationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testBuildInitialSteps() {
        NSLocale.setCurrentTest(Locale(identifier: "en_US"))

        let (items, sections) = buildMedicationItems()
        let medTracker = SBAMedicationTrackingStepNavigator(identifier: "Test", items: items, sections: sections)
        XCTAssertEqual(medTracker.items.count, items.count)
        XCTAssertEqual(medTracker.sections?.count ?? 0, sections.count)
        
        let selectionStep = medTracker.selectionStep as! SBATrackedSelectionStepObject
        XCTAssertEqual(selectionStep.items.count, items.count)
        XCTAssertEqual(selectionStep.sections?.count ?? 0, sections.count)
        XCTAssertEqual(selectionStep.title, "What medications are you taking?")
        XCTAssertEqual(selectionStep.detail, "Select all that apply")
        
        guard let reviewStep = medTracker.reviewStep as? SBATrackedItemsReviewStepObject else {
            XCTFail("Failed to build review step. Exiting.")
            return
        }
        XCTAssertEqual(reviewStep.items.count, items.count)
        XCTAssertEqual(reviewStep.sections?.count ?? 0, sections.count)
        XCTAssertEqual(reviewStep.title, reviewStep.addDetailsTitle)
        XCTAssertEqual(reviewStep.detail, reviewStep.addDetailsSubtitle)
        XCTAssertEqual(reviewStep.addDetailsTitle, "Add medication details")
        XCTAssertEqual(reviewStep.addDetailsSubtitle, "Select to add your medication dosing information and schedule(s).")
        XCTAssertEqual(reviewStep.reviewTitle, "Review medications")
        if let action = reviewStep.actions?[.addMore] {
            XCTAssertEqual(action.buttonTitle, "Edit medication list")
        } else {
            XCTFail("Step action does not include `.addMore`")
        }
        
        XCTAssertEqual(medTracker.detailStepTemplates?.count ?? 0, 1)
        guard let detailStep = medTracker.detailStepTemplates?.first as? SBATrackedMedicationDetailStepObject else {
            XCTFail("Failed to build the detail step. \(String(describing: medTracker.detailStepTemplates)) ")
            return
        }
        
        // Test fresh data source with no previous details
        let taskPath = RSDTaskPath(task: RSDTaskObject(identifier: "medTracking", stepNavigator: medTracker))
        if let dataSource = detailStep.instantiateDataSource(with: taskPath, for: Set()) as? SBATrackedMedicationDetailsDataSource {
            XCTAssertEqual(dataSource.sections.count, 3)
            XCTAssertEqual(dataSource.sections[0].identifier, "dosage")
            XCTAssertEqual(dataSource.sections[1].identifier, "schedules")
            XCTAssertEqual(dataSource.sections[2].identifier, "addSchedule")
            
            // Test changing the data source by adding a schedule
            dataSource.addScheduleItem()
            XCTAssertEqual(dataSource.sections.count, 3)
            XCTAssertEqual(dataSource.sections[0].identifier, "dosage")
            XCTAssertEqual(dataSource.sections[1].identifier, "schedules")
            XCTAssertEqual(dataSource.sections[1].tableItems.count, 2)
            XCTAssertEqual(dataSource.sections[2].identifier, "addSchedule")
            
            // Test changing the data source schedule at anytime to selected
            dataSource.scheduleAtAnytimeChanged(selected: true)
            XCTAssertEqual(dataSource.sections.count, 2)
            XCTAssertEqual(dataSource.sections[0].identifier, "dosage")
            XCTAssertEqual(dataSource.sections[1].identifier, "schedules")
            XCTAssertEqual(dataSource.sections[1].tableItems.count, 1)
        } else {
            XCTFail("detail data source not instantiated")
        }
        
        var medication = SBAMedicationAnswer(identifier: detailStep.identifier)
        medication.dosage = "10 mg"
        let monThruWed: [RSDWeekday] = [.monday, .tuesday, .wednesday]
        let friThruSun: [RSDWeekday] = [.friday, .saturday, .sunday]
        medication.scheduleItems = Set([RSDWeeklyScheduleObject(timeOfDayString: "07:00", daysOfWeek: Set(monThruWed)), RSDWeeklyScheduleObject(timeOfDayString: "17:00", daysOfWeek: Set(friThruSun))])
        detailStep.updatePreviousAnswer(answer: medication)
        if let dataSource = detailStep.instantiateDataSource(with: taskPath, for: Set()) as? SBATrackedMedicationDetailsDataSource {
            XCTAssertEqual(dataSource.sections.count, 3)
            
            XCTAssertEqual(dataSource.sections[0].identifier, "dosage")
            if let dosageTableItem = dataSource.sections[0].tableItems[0] as? RSDTextInputTableItem {
                XCTAssertEqual(dosageTableItem.answerText, "10 mg")
            } else {
                XCTFail("dosage table item not instantiated")
            }
            
            XCTAssertEqual(dataSource.sections[1].identifier, "schedules")
            XCTAssertEqual(dataSource.sections[1].tableItems.count, 2)
            if let scheduleTableItem = dataSource.sections[1].tableItems[0] as? SBATrackedWeeklyScheduleTableItem {
                XCTAssertEqual(RSDDateCoderObject.hourAndMinutesOnly.inputFormatter.string(from: scheduleTableItem.time!), "07:00")
                XCTAssertEqual(scheduleTableItem.weekdays?.count, 3)
                XCTAssertTrue(scheduleTableItem.weekdays!.contains(monThruWed[0]))
                XCTAssertTrue(scheduleTableItem.weekdays!.contains(monThruWed[1]))
                XCTAssertTrue(scheduleTableItem.weekdays!.contains(monThruWed[2]))
            } else {
                XCTFail("schedule table item 1 not instantiated")
            }
            
            XCTAssertEqual(dataSource.sections[2].identifier, "addSchedule")
        } else {
            XCTFail("detail data source not instantiated")
        }
        
        medication.dosage = "100 mg"
        medication.scheduleItems = Set([RSDWeeklyScheduleObject(timeOfDayString: nil, daysOfWeek: Set())])
        detailStep.updatePreviousAnswer(answer: medication)
        if let dataSource = detailStep.instantiateDataSource(with: taskPath, for: Set()) as? SBATrackedMedicationDetailsDataSource {
            XCTAssertEqual(dataSource.sections.count, 2)
            XCTAssertEqual(dataSource.sections[0].identifier, "dosage")
            if let dosageTableItem = dataSource.sections[0].tableItems[0] as? RSDTextInputTableItem {
                XCTAssertEqual(dosageTableItem.answerText, "100 mg")
            } else {
                XCTFail("dosage table item not instantiated")
            }
            
            XCTAssertEqual(dataSource.sections[1].identifier, "schedules")
            XCTAssertEqual(dataSource.sections[1].tableItems.count, 1)
            if let scheduleTableItem = dataSource.sections[1].tableItems[0] as? SBATrackedWeeklyScheduleTableItem {
                XCTAssertNil(scheduleTableItem.time)
                XCTAssertEqual(scheduleTableItem.weekdays?.count, 0)
            } else {
                XCTFail("schedule table item 1 not instantiated")
            }
        } else {
            XCTFail("detail data source not instantiated")
        }
    }
    
    func testMedicationTrackingNavigation_FirstRun() {
        NSLocale.setCurrentTest(Locale(identifier: "en_US"))
        
        let (items, sections) = buildMedicationItems()
        let medTracker = SBAMedicationTrackingStepNavigator(identifier: "Test", items: items, sections: sections)
    
        var taskResult: RSDTaskResult = RSDTaskResultObject(identifier: "medication")
        
        let (firstStep, _) = medTracker.step(after: nil, with: &taskResult)
        XCTAssertNotNil(firstStep)
        
        guard let selectionStep = firstStep as? SBATrackedSelectionStepObject else {
            XCTFail("Failed to create the selection step. Exiting.")
            return
        }
        
        XCTAssertNil(medTracker.step(before: selectionStep, with: &taskResult))
        XCTAssertEqual(medTracker.step(with: selectionStep.identifier)?.identifier, selectionStep.identifier)
        XCTAssertFalse(medTracker.hasStep(before: selectionStep, with: taskResult))
        XCTAssertTrue(medTracker.hasStep(after: selectionStep, with: taskResult))

        guard let firstResult = selectionStep.instantiateStepResult() as? SBATrackedItemsResult else {
            XCTFail("Failed to create the expected result. Exiting.")
            return
        }
        var selectionResult = firstResult
        selectionResult.updateSelected(to: ["medA2", "medB4"], with: selectionStep.items)
        taskResult.appendStepHistory(with: selectionResult)
        
        // Next step after selection is review.
        let (secondStep, _) = medTracker.step(after: firstStep, with: &taskResult)
        XCTAssertNotNil(secondStep)
        
        // Check that the med tracker can navigate to any step by identifier
        XCTAssertEqual(medTracker.step(with: "medA2")?.identifier, "medA2")
        XCTAssertEqual(medTracker.step(with: "medB4")?.identifier, "medB4")
        XCTAssertNil(medTracker.step(with: "medA1"))
        
        guard let initialReviewStep = secondStep as? SBATrackedItemsReviewStepObject else {
            XCTFail("Failed to create the initial review step. Exiting.")
            return
        }
        
        // The review should use the default title for forward navigation if the answers are not complete.
        XCTAssertNil(initialReviewStep.action(for: .navigation(.goForward), on: initialReviewStep))
    
        XCTAssertNil(medTracker.step(before: initialReviewStep, with: &taskResult))
        XCTAssertEqual(medTracker.step(with: initialReviewStep.identifier)?.identifier, initialReviewStep.identifier)
        XCTAssertFalse(medTracker.hasStep(before: initialReviewStep, with: taskResult))
        XCTAssertTrue(medTracker.hasStep(after: initialReviewStep, with: taskResult))
        
        guard let secondResult = initialReviewStep.instantiateStepResult() as? SBAMedicationTrackingResult else {
            XCTFail("Failed to create the expected result. Exiting.")
            return
        }
        XCTAssertEqual(secondResult.selectedAnswers.count, 2)
        XCTAssertFalse(secondResult.hasRequiredValues)
        
        taskResult.appendStepHistory(with: secondResult)
        
        (secondStep as? SBATrackedItemsReviewStepObject)?.nextStepIdentifier = "medA2"
        let (thirdStep, _) = medTracker.step(after: secondStep, with: &taskResult)
        XCTAssertNotNil(thirdStep)
        XCTAssertEqual(thirdStep?.identifier, "medA2")
        
        guard let medA2DetailsStep = thirdStep as? SBATrackedMedicationDetailStepObject else {
            XCTFail("Failed to create the expected step. Exiting.")
            return
        }
        
        XCTAssertEqual(medTracker.step(before: medA2DetailsStep, with: &taskResult)?.identifier, "review")
        XCTAssertTrue(medTracker.hasStep(before: medA2DetailsStep, with: taskResult))
        XCTAssertTrue(medTracker.hasStep(after: medA2DetailsStep, with: taskResult))
        XCTAssertTrue(medA2DetailsStep.instantiateStepResult() is RSDCollectionResult)

        taskResult.appendStepHistory(with: medA2Result())
        
        let (fourthStep, _) = medTracker.step(after: thirdStep, with: &taskResult)
        XCTAssertNotNil(fourthStep)
        XCTAssertEqual(fourthStep?.identifier, "review")
        
        // Next step after selection is review.
        let (fifthStep, _) = medTracker.step(after: fourthStep, with: &taskResult)
        XCTAssertNotNil(fifthStep)
        
        guard let medB4DetailsStep = fifthStep as? SBATrackedMedicationDetailStepObject else {
            XCTFail("Failed to create the expected step. Exiting.")
            return
        }
        
        XCTAssertEqual(medTracker.step(before: medB4DetailsStep, with: &taskResult)?.identifier, "review")
        XCTAssertTrue(medTracker.hasStep(before: medB4DetailsStep, with: taskResult))
        XCTAssertTrue(medTracker.hasStep(after: medB4DetailsStep, with: taskResult))
        XCTAssertTrue(medB4DetailsStep.instantiateStepResult() is RSDCollectionResult)
        
        taskResult.appendStepHistory(with: medB4Result())
        
        // Next step after selection is review.
        let (sixthstep, _) = medTracker.step(after: fifthStep, with: &taskResult)
        XCTAssertNotNil(sixthstep)
        
        guard let finalReviewStep = sixthstep as? SBATrackedItemsReviewStepObject else {
            XCTFail("Failed to return the final review step. Exiting. \(String(describing: sixthstep))")
            return
        }
        
        XCTAssertNil(medTracker.step(before: finalReviewStep, with: &taskResult))
        XCTAssertEqual(finalReviewStep.identifier, initialReviewStep.identifier)
        XCTAssertFalse(medTracker.hasStep(before: finalReviewStep, with: taskResult))
        
        // TODO: mdephillips 7/1/18 check reminders or logging
        //        XCTAssertFalse(medTracker.hasStep(after: finalReviewStep, with: taskResult))
        //        checkFinalReviewStep(finalReviewStep)
    }
    
    func testMedicationTrackingNavigation_FirstRun_CustomOrder() {
        NSLocale.setCurrentTest(Locale(identifier: "en_US"))
        
        let (items, sections) = buildMedicationItems()
        let medTracker = SBAMedicationTrackingStepNavigator(identifier: "Test", items: items, sections: sections)
        
        var taskResult: RSDTaskResult = RSDTaskResultObject(identifier: "medication")
        
        let (step1, _) = medTracker.step(after: nil, with: &taskResult)
        guard let selectionStep = step1 as? SBATrackedSelectionStepObject else {
            XCTFail("Failed to create the selection step. Exiting.")
            return
        }
         
        guard let firstResult = selectionStep.instantiateStepResult() as? SBATrackedItemsResult else {
            XCTFail("Failed to create the expected result. Exiting.")
            return
        }
        var selectionResult = firstResult
        selectionResult.updateSelected(to: ["medA2", "medB4"], with: selectionStep.items)
        taskResult.appendStepHistory(with: selectionResult)
        
        let (step2, _) = medTracker.step(after: selectionStep, with: &taskResult)
        guard let initialReviewStep = step2 as? SBATrackedItemsReviewStepObject else {
            XCTFail("Failed to create the initial review step. Exiting.")
            return
        }
        guard let secondResult = initialReviewStep.instantiateStepResult() as? SBAMedicationTrackingResult else {
            XCTFail("Failed to create the expected result. Exiting.")
            return
        }
        
        taskResult.appendStepHistory(with: secondResult)
        
        // Set up the review step with a custom order by setting the next step identifier
        initialReviewStep.nextStepIdentifier = "medB4"
        
        let (thirdStep, _) = medTracker.step(after: initialReviewStep, with: &taskResult)

        XCTAssertNotNil(thirdStep)
        XCTAssertEqual(thirdStep?.identifier, "medB4")
        
        guard let medB4DetailsStep = thirdStep as? SBATrackedMedicationDetailStepObject else {
            XCTFail("Failed to create the expected step. Exiting.")
            return
        }
        
        XCTAssertTrue(medB4DetailsStep.instantiateStepResult() is RSDCollectionResult)
        
        taskResult.appendStepHistory(with: medB4Result())
        
        let (fourthStep, _) = medTracker.step(after: thirdStep, with: &taskResult)
        XCTAssertNotNil(fourthStep)
        XCTAssertEqual(fourthStep?.identifier, "review")
        
        // Next step after selection is review.
        let (fifthStep, _) = medTracker.step(after: fourthStep, with: &taskResult)
        XCTAssertNotNil(fifthStep)
        
        guard let medA2DetailsStep = fifthStep as? SBATrackedMedicationDetailStepObject else {
            XCTFail("Failed to create the expected step. Exiting.")
            return
        }
        
        XCTAssertEqual(medTracker.step(before: medA2DetailsStep, with: &taskResult)?.identifier, "review")
        XCTAssertTrue(medTracker.hasStep(before: medA2DetailsStep, with: taskResult))
        XCTAssertTrue(medTracker.hasStep(after: medA2DetailsStep, with: taskResult))
        XCTAssertTrue(medA2DetailsStep.instantiateStepResult() is RSDCollectionResult)

        taskResult.appendStepHistory(with: medA2Result())
        
        // Next step after selection is review.
        let (sixthStep, _) = medTracker.step(after: fifthStep, with: &taskResult)
        XCTAssertNotNil(fifthStep)
        
        guard let finalReviewStep = sixthStep as? SBATrackedItemsReviewStepObject else {
            XCTFail("Failed to return the final review step. Exiting. \(String(describing: fifthStep))")
            return
        }
        
        XCTAssertNil(medTracker.step(before: finalReviewStep, with: &taskResult))
        XCTAssertEqual(finalReviewStep.identifier, "review")
        XCTAssertFalse(medTracker.hasStep(before: finalReviewStep, with: taskResult))
        
        // TODO: mdephillips 7/1/18 check reminders or logging
//        XCTAssertFalse(medTracker.hasStep(after: finalReviewStep, with: taskResult))
//        checkFinalReviewStep(finalReviewStep)
    }
    
    func testMedicationTrackingNavigation_FollowupRun() {
        NSLocale.setCurrentTest(Locale(identifier: "en_US"))
        
        let (items, sections) = buildMedicationItems()
        let medTracker = SBAMedicationTrackingStepNavigator(identifier: "Test", items: items, sections: sections)
        
        var initialResult = SBAMedicationTrackingResult(identifier: medTracker.reviewStep!.identifier)
        var medA3 = SBAMedicationAnswer(identifier: "medA3")
        medA3.dosage = "1"
        medA3.scheduleItems = [RSDWeeklyScheduleObject(timeOfDayString: "08:00", daysOfWeek: [.monday, .wednesday, .friday])]
        var medC3 = SBAMedicationAnswer(identifier: "medC3")
        medC3.dosage = "1"
        medC3.scheduleItems = [RSDWeeklyScheduleObject(timeOfDayString: "20:00", daysOfWeek: [.sunday, .thursday])]
        initialResult.medications = [medA3, medC3]
        let clientData = try! initialResult.clientData()
        
        medTracker.previousClientData = clientData
        
        // Check initial state
        XCTAssertNotNil(medTracker.getSelectionStep())
        XCTAssertNotNil(medTracker.getReviewStep())
        
        if let detailsStep = medTracker.step(with: "medA3") as? SBATrackedItemDetailsStepObject {
            XCTAssertNotNil(detailsStep.trackedItem)
            XCTAssertNotNil(detailsStep.previousAnswer)
            XCTAssertEqual(detailsStep.previousAnswer?.hasRequiredValues, true)
        } else {
            XCTFail("Step not found or not of expected type.")
        }
        if let detailsStep = medTracker.step(with: "medC3") as? SBATrackedItemDetailsStepObject {
            XCTAssertNotNil(detailsStep.trackedItem)
            XCTAssertNotNil(detailsStep.previousAnswer)
            XCTAssertEqual(detailsStep.previousAnswer?.hasRequiredValues, true)
        } else {
            XCTFail("Step not found or not of expected type.")
        }

        // TODO: mdephillips 7/4/18 happy 4th! add the logging step back in once that is completed
        
//        var taskResult: RSDTaskResult = RSDTaskResultObject(identifier: "logMedications")
        // For the case where the meds have been set, this should jump to logging the medication results.
//        let (firstStep, _) = medTracker.step(after: nil, with: &taskResult)
        
//        guard let loggingStep = firstStep as? SBAMedicationLoggingStepObject else {
//            XCTFail("First step not of expected type. For a follow-up run should start with logging step.")
//            return
//        }
//
//        XCTAssertEqual(loggingStep.result?.selectedAnswers.count, 2)
//        XCTAssertFalse(medTracker.hasStep(after: loggingStep, with: taskResult))
//        XCTAssertFalse(medTracker.hasStep(before: loggingStep, with: taskResult))
//        XCTAssertNil(medTracker.step(before: loggingStep, with: &taskResult))
//        XCTAssertNil(medTracker.step(after: loggingStep, with: &taskResult).step)
    }
    
    // MARK: Shared tests
    
    func checkFinalReviewStep(_ finalReviewStep: SBATrackedItemsReviewStepObject) {
        
        // The review should use the "Submit" title for forward navigation if the answers are not complete.
        if let action = finalReviewStep.action(for: .navigation(.goForward), on: finalReviewStep) {
            XCTAssertEqual(action.buttonTitle, "Submit")
        } else {
            XCTFail("Step action does not include `.goForward`")
        }
        
        guard let finalResult = finalReviewStep.result as? SBAMedicationTrackingResult else {
            XCTFail("Failed to create the expected result. Exiting.")
            return
        }
        XCTAssertEqual(finalResult.selectedAnswers.count, 2)
        XCTAssertTrue(finalResult.hasRequiredValues)
        
        // Inspect the final result for expected values.
        guard let answerA2 = finalResult.selectedAnswers.first as? SBAMedicationAnswer,
            let answerB4 = finalResult.selectedAnswers.last as? SBAMedicationAnswer,
            answerA2.identifier != answerB4.identifier else {
                XCTFail("Failed to create the expected result. Exiting.")
                return
        }
        
        XCTAssertEqual(answerA2.identifier, "medA2")
        XCTAssertEqual(answerA2.dosage, "5 ml")
        XCTAssertEqual(answerA2.scheduleItems?.count, 2)
        if let sortedItems = answerA2.scheduleItems?.sorted() {
            XCTAssertEqual(sortedItems.first?.timeOfDayString, "08:30")
            XCTAssertEqual(sortedItems.first?.daysOfWeek, [.monday, .wednesday, .friday])
            XCTAssertEqual(sortedItems.last?.timeOfDayString, "20:00")
            XCTAssertEqual(sortedItems.last?.daysOfWeek, [.sunday])
        }
        
        XCTAssertEqual(answerB4.identifier, "medB4")
        XCTAssertEqual(answerB4.dosage, "1/20 mg")
        XCTAssertEqual(answerB4.scheduleItems?.count, 1)
        if let sortedItems = answerB4.scheduleItems?.sorted() {
            XCTAssertEqual(sortedItems.first?.timeOfDayString, "07:30")
            XCTAssertEqual(sortedItems.first?.daysOfWeek, RSDWeekday.all)
        }
    }
    
    // Check functions that should remain the same for all instances.
    func checkScheduleTime(_ scheduleTime: RSDInputField, _ debug: String) {
        XCTAssertEqual(scheduleTime.dataType, .base(.date), debug)
        XCTAssertEqual(scheduleTime.inputUIHint, .picker, debug)
        if let range = scheduleTime.range as? RSDDateRange {
            XCTAssertNotNil(range.defaultDate, debug)
            if let dateCoder = range.dateCoder as? RSDDateCoderObject {
                XCTAssertEqual(dateCoder.rawValue, "HH:mm", debug)
            } else {
                XCTFail("\(String(describing:range.dateCoder)) not expected type. \(debug)")
            }
        } else {
            XCTFail("\(String(describing: scheduleTime.range)) not expected type. \(debug)")
        }
        if let formatter = scheduleTime.formatter as? DateFormatter {
            XCTAssertEqual(formatter.dateStyle, .none, debug)
            XCTAssertEqual(formatter.timeStyle, .short, debug)
        } else {
            XCTFail("\(String(describing: scheduleTime.formatter)) not expected type. \(debug)")
        }
        XCTAssertNil(scheduleTime.textFieldOptions, debug)
    }
    
    func checkScheduleDays(_ scheduleDays: RSDInputField, _ debug: String) {
        XCTAssertEqual(scheduleDays.dataType, .collection(.multipleChoice, .integer), debug)
        XCTAssertEqual(scheduleDays.inputUIHint, .popover, debug)
        XCTAssertNil(scheduleDays.range, debug)
        XCTAssertNil(scheduleDays.textFieldOptions, debug)
        XCTAssertNotNil(scheduleDays.formatter as? RSDWeeklyScheduleFormatter,
                        "\(String(describing: scheduleDays.formatter)) not expected type. \(debug)")
        do {
            try scheduleDays.validate()
        } catch let err {
            XCTFail("Failed to validate the input field. \(err)")
        }
        if let popover = scheduleDays as? RSDPopoverInputFieldObject,
            let choiceField = popover.inputFields.first as? RSDChoiceInputFieldObject {
            XCTAssertEqual(choiceField.choices.count, 7, debug)
        } else {
            XCTFail("\(String(describing: scheduleDays)) not expected type. \(debug)")
        }
    }
}

// Helper methods

func medB4Result() -> SBAMedicationDetailsResultObject {
    var result = SBAMedicationDetailsResultObject(identifier: "medB4")
    result.dosage = "1/20 mg"
    let schedule0 = RSDWeeklyScheduleObject(timeOfDayString: "07:30", daysOfWeek: Set([.monday, .wednesday, .friday]))
    let schedule1 = RSDWeeklyScheduleObject(timeOfDayString: "20:00", daysOfWeek: Set(RSDWeekday.all))
    result.schedules = [schedule0, schedule1]
    return result
}

func medA2Result() -> SBAMedicationDetailsResultObject {
    var result = SBAMedicationDetailsResultObject(identifier: "medA2")
    result.dosage = "5 ml"
    let schedule0 = RSDWeeklyScheduleObject(timeOfDayString: "08:30", daysOfWeek: Set([.monday, .wednesday, .friday]))
    let schedule1 = RSDWeeklyScheduleObject(timeOfDayString: "20:00", daysOfWeek: Set([.sunday]))
    result.schedules = [schedule0, schedule1]
    return result
}

func buildMedicationItems() -> (items: [SBAMedicationItem], sections: [SBATrackedSection]) {
    let items = [   SBAMedicationItem(identifier: "medA1", sectionIdentifier: "section1"),
                    SBAMedicationItem(identifier: "medA2", sectionIdentifier: "section2"),
                    SBAMedicationItem(identifier: "medA3", sectionIdentifier: "section3"),
                    SBAMedicationItem(identifier: "medA4", sectionIdentifier: "section4"),
                    SBAMedicationItem(identifier: "medB1", sectionIdentifier: "section1"),
                    SBAMedicationItem(identifier: "medB2", sectionIdentifier: "section2"),
                    SBAMedicationItem(identifier: "medB3", sectionIdentifier: "section3"),
                    SBAMedicationItem(identifier: "medB4", sectionIdentifier: "section4"),
                    SBAMedicationItem(identifier: "medC1", sectionIdentifier: "section1"),
                    SBAMedicationItem(identifier: "medC2", sectionIdentifier: "section2"),
                    SBAMedicationItem(identifier: "medC3", sectionIdentifier: "section3"),
                    SBAMedicationItem(identifier: "medC4", sectionIdentifier: "section4"),
                    SBAMedicationItem(identifier: "medNoSection1", sectionIdentifier: nil),
                    SBAMedicationItem(identifier: "medFooSection1", sectionIdentifier: "Foo"),
                    SBAMedicationItem(identifier: "medFooSection2", sectionIdentifier: "Foo"),
                    ]
    
    let sections = [    SBATrackedSectionObject(identifier: "section1"),
                        SBATrackedSectionObject(identifier: "section2"),
                        SBATrackedSectionObject(identifier: "section3"),
                        SBATrackedSectionObject(identifier: "section4"),
                        ]
    
    return (items, sections)
}
