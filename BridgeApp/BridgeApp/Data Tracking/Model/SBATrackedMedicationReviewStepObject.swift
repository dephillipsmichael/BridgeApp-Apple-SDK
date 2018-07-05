//
//  SBATrackedMedicationReviewStepObject.swift
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

/// A step used for review selected medication and their details
open class SBATrackedMedicationReviewStepObject : SBATrackedItemsReviewStepObject, RSDStepViewControllerVendor {
    
    #if !os(watchOS)
    /// Override to return a medication tracking review step view controller.
    open func instantiateViewController(with taskPath: RSDTaskPath) -> (UIViewController & RSDStepController)? {
        return SBATrackedMedicationReviewStepViewController(step: self)
    }
    #endif
    
    /// Override to return a `SBATrackedMedicationReviewDataSource`.
    open override func instantiateDataSource(with taskPath: RSDTaskPath, for supportedHints: Set<RSDFormUIHint>) -> RSDTableDataSource? {
        return SBATrackedMedicationReviewDataSource(step: self, taskPath: taskPath)
    }
}

/// A data source used to handle tracked medication review.
open class SBATrackedMedicationReviewDataSource : SBATrackingDataSource, RSDModalStepDataSource, RSDModalStepTaskControllerDelegate {

    fileprivate var mostRecentResult: SBAMedicationTrackingResult? {
        return self.trackingResult() as? SBAMedicationTrackingResult
    }
    
    /// Overridable class function for building the sections of the table.
    /// - parameters:
    ///     - step: The `SBATrackedItemsStep` for this data source.
    ///     - initialResult: The initial result (if any).
    /// - returns:
    ///     - sections: The built table sections.
    ///     - itemGroups: The associated item groups.
    override open class func buildSections(step: SBATrackedItemsStep, initialResult: SBATrackedItemsResult?) -> (sections: [RSDTableSection], itemGroups: [RSDTableItemGroup]) {
        guard let result = initialResult else {
            assertionFailure("A non-nil initial result is expected for logging items")
            return ([], [])
        }
        
        let review = buildReviewSections(step: step, result: result)
        var itemGroups = review.itemGroups
        var sections = review.sections
        
        let actionType: RSDUIActionType = .addMore
        if let uiStep = step as? RSDUIActionHandler, let action = uiStep.action(for: actionType, on: step) {
            let tableItem = SBAModalSelectionTableItem(identifier: actionType.stringValue, rowIndex: 0, reuseIdentifier: RSDFormUIHint.modalButton.stringValue, action: action)
            itemGroups.append(RSDTableItemGroup(beginningRowIndex: 0, items: [tableItem]))
            sections.append(RSDTableSection(identifier: "addMore", sectionIndex: 1, tableItems: [tableItem]))
        }
        
        return (sections, itemGroups)
    }
    
    /// Build the review sections of the table. This is called by `buildSections(step:initialResult)` to get
    /// the review sections of the table. That method will then append an `.addMore` section if appropriate.
    open class func buildReviewSections(step: SBATrackedItemsStep, result: SBATrackedItemsResult) -> (sections: [RSDTableSection], itemGroups: [RSDTableItemGroup]) {
        
        let inputField = RSDChoiceInputFieldObject(identifier: step.identifier, choices: result.selectedAnswers, dataType: .collection(.multipleChoice, .string), uiHint: .logging)
        let trackedItems = result.selectedAnswers.enumerated().map { (idx, item) -> RSDTableItem in
            let choice: RSDChoice = step.items.first(where: { $0.identifier == item.identifier }) ?? item
            return self.instantiateTableItem(at: idx, inputField: inputField, itemAnswer: item, choice: choice)
        }
        
        let itemGroups: [RSDTableItemGroup] = [RSDTableItemGroup(beginningRowIndex: 0, items: trackedItems)]
        let sections: [RSDTableSection] = [RSDTableSection(identifier: "review", sectionIndex: 0, tableItems: trackedItems)]
        
        return (sections, itemGroups)
    }
    
    /// Override the instantiation of the table item to return a medication review table item
    open class func instantiateTableItem(at rowIndex: Int, inputField: RSDInputField, itemAnswer: SBATrackedItemAnswer, choice: RSDChoice) -> RSDTableItem {

        guard let medAnswer = itemAnswer as? SBAMedicationAnswer else {
            return RSDTextTableItem(rowIndex: rowIndex, text: "Invalid SBATrackedItemAnswer format")
        }

        let reviewItem = SBATrackedMedicationReviewItem(medication: medAnswer, rowIndex: rowIndex, reuseIdentifier: SBATrackedMedicationReviewCell.reuseId)
        return reviewItem
    }
    
    /// Call when a review item is selected, this will add a details result to the step history
    /// that will be used to create the correct details step.
    func reviewItemSelected(identifier: String) {
        if let currentResult = self.mostRecentResult,
            let existingDetailsResult = currentResult.medications.first(where: { $0.identifier == identifier }),
            let reviewStep = self.step as? SBATrackedMedicationReviewStepObject {
            reviewStep.nextStepIdentifier = existingDetailsResult.identifier
        }
    }

    /// Returns the selection step.
    open func step(for tableItem: RSDModalStepTableItem) -> RSDStep {
        guard let step = (self.taskPath.task?.stepNavigator as? SBATrackedItemsStepNavigator)?.getSelectionStep() as? SBATrackedItemsStep
            else {
                assertionFailure("Expecting the task navigator to be a tracked items navigator.")
                return RSDUIStepObject(identifier: tableItem.identifier)
        }
        step.result = self.trackingResult()
        return step
    }
    
    /// The calling table view controller will present a step view controller for the modal step. This method
    /// should set up the task controller for the step and handle any other task management required before
    /// presenting the step.
    ///
    /// - parameters:
    ///     - stepController: The step controller that was instantiated to run the step.
    ///     - tableItem: The table item that was selected.
    open func willPresent(_ stepController: RSDStepController, from tableItem: RSDModalStepTableItem) {
        guard let task = taskPath.task else {
            assertionFailure("Failed to set the task controller because the current task is nil.")
            return
        }
        
        // Set up the path and the task controller for the current step. For this case, we want a new task
        // path that uses the task from *this* taskPath as it's source, but which does not directly edit this
        // task path.
        let path = RSDTaskPath(task: task)
        setupModal(stepController, path: path, tableItem: tableItem)
    }
    
    internal func setupModal(_ stepController: RSDStepController, path: RSDTaskPath, tableItem: RSDModalStepTableItem) {
        path.currentStep = stepController.step
        let taskController = RSDModalStepTaskController()
        _currentTaskController = taskController
        _currentTableItem = tableItem
        taskController.taskPath = path
        taskController.stepController = stepController
        taskController.delegate = self
        stepController.taskController = taskController
    }
    
    internal var _currentTaskController: RSDModalStepTaskController?
    internal var _currentTableItem: RSDModalStepTableItem?
    
    // MARK: RSDModalStepTaskControllerDelegate
    
    open func goForward(with taskController: RSDModalStepTaskController) {
        if let _ = _currentTableItem as? SBAModalSelectionTableItem,
            let result = taskController.taskPath.result.findResult(for: taskController.stepController.step) as? SBATrackedItemsResult {
            
            // Let the delegate know that things are changing.
            self.delegate?.tableDataSourceWillBeginUpdate(self)
            
            // Update the result set for this source.
            var stepResult = self.trackingResult()
            stepResult.updateSelected(to: result.selectedIdentifiers, with: trackedStep.items)
            self.taskPath.appendStepHistory(with: stepResult)
            let changes = self.reloadDataSource(with: result)
            
            // reload the table delegate.
            self.delegate?.tableDataSourceDidEndUpdate(self, addedRows: changes.addedRows, removedRows: changes.removedRows)
        }
        self.delegate?.tableDataSource(self, didFinishWith: taskController.stepController)
        _currentTaskController = nil
        _currentTableItem = nil
    }
    
    /// Default behavior is to dismiss the view controller without changes.
    open func goBack(with taskController: RSDModalStepTaskController) {
        self.delegate?.tableDataSource(self, didFinishWith: taskController.stepController)
        _currentTaskController = nil
        _currentTableItem = nil
    }
}

/// The medication review table item is tracked using the result object.
open class SBATrackedMedicationReviewItem : RSDModalStepTableItem {

    /// The result object associated with this table item.
    public var medication: SBAMedicationAnswer

    /// Initialize a new SBATrackedMedicationReviewItem.
    /// - parameters:
    ///     - identifier: The cell identifier.
    ///     - rowIndex: The index of this item relative to all rows in the section in which this item resides.
    ///     - reuseIdentifier: The string to use as the reuse identifier.
    public init(medication: SBAMedicationAnswer, rowIndex: Int, reuseIdentifier: String = RSDFormUIHint.logging.rawValue) {
        self.medication = medication
        super.init(identifier: medication.identifier, rowIndex: rowIndex, reuseIdentifier: reuseIdentifier)
    }
}
