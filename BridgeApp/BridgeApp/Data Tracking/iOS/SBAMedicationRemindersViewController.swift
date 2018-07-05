//
//  SBAMedicationRemindersViewController.swift
//  mPower2
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

import UIKit
import BridgeApp

class SBAMedicationRemindersViewController: RSDTableStepViewController {
    
    func showReminderDetailsTask() {
        do {
            // Instantiate and create the reminder details task
            let resourceTransformer = RSDResourceTransformerObject(resourceName: "MedicationReminderDetails")
            let task = try RSDFactory.shared.decodeTask(with: resourceTransformer)
            let taskPath = RSDTaskPath(task: task)
            
            // See if we currently have any reminder intervals saved and, if so, add them to the result
            // for our new task so they are prepopulated for the user
            if let intervals = intervals(from: taskController.taskPath),
                intervals.count > 0,
                let stepNavigator = task.stepNavigator as? RSDConditionalStepNavigator,
                let firstStep = stepNavigator.steps.first {
                
                update(taskPath: taskPath, with: intervals, for: firstStep.identifier)
            }
            
            let vc = RSDTaskViewController(taskPath: taskPath)
            vc.delegate = self
            present(vc, animated: true, completion: nil)
            
        } catch let err {
            fatalError("Failed to decode the task. \(err)")
        }
    }

    override func setupModel() {
        
        super.setupModel()
        
        // We want a section label above the first choice cell, which doesn't have one by default.
        // So we set the title of that table item
        (tableData?.sections.first)?.title = "Add reminders"
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Override default behavior to show the details task so the user can select their intervals
        showReminderDetailsTask()
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        // Get the cell from super and update the label with the cancatenation of our current reminder intervals
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        let labelString: String = {
            if let intervals = intervals(from: taskController.taskPath), intervals.count > 0 {
                return intervals.compactMap { return String($0) }.joined(separator: ", ") + " minutes before medication time."
            }
            else {
                return "(no reminders set)"
            }
        }()
        cell.textLabel?.text = labelString
        
        // Also add a disclosure indicator
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    
    func intervals(from taskPath: RSDTaskPath) -> [Int]? {
        
        guard taskPath.result.stepHistory.count > 0,
            let collectionResult = taskPath.result.stepHistory.first as? RSDCollectionResultObject else {
                return nil
        }

        var intervalsSelected = [Int]()
        for intervalResult in collectionResult.inputResults {
            if let intervalAnswerResult = intervalResult as? RSDAnswerResultObject,
                let intervalValueArray = intervalAnswerResult.value as? [Int] {
                for intervalInt in intervalValueArray {
                    intervalsSelected.append(intervalInt)
                }
            }
        }
        return intervalsSelected
    }
    
    func update(taskPath: RSDTaskPath, with intervals: [Int], for stepIdentifier: String) {
        
        var previousResult = RSDCollectionResultObject(identifier: stepIdentifier)
        var answerResult = RSDAnswerResultObject(identifier: stepIdentifier,
                                                 answerType: RSDAnswerResultType(baseType: .integer,
                                                                                 sequenceType: .array,
                                                                                 formDataType: .collection(.multipleChoice, .integer),
                                                                                 dateFormat: nil,
                                                                                 unit: nil,
                                                                                 sequenceSeparator: nil))
        answerResult.value = intervals
        previousResult.inputResults = [answerResult]
        taskPath.appendStepHistory(with: previousResult)
    }
}

extension SBAMedicationRemindersViewController: RSDTaskViewControllerDelegate {
    func taskController(_ taskController: RSDTaskController, didFinishWith reason: RSDTaskFinishReason, error: Error?) {
        dismiss(animated: true, completion: nil)
    }
    
    func taskController(_ taskController: RSDTaskController, readyToSave taskPath: RSDTaskPath) {
        if let intervals = intervals(from: taskPath),
            let stepNavigator = self.taskController.taskPath.task?.stepNavigator as? RSDConditionalStepNavigator,
            let firstStep = stepNavigator.steps.first {
            
            // Update our current task results with the intervals selected by the user
            update(taskPath: self.taskController.taskPath, with: intervals, for: firstStep.identifier)
            tableView.reloadData()
        }
    }

    func taskController(_ taskController: RSDTaskController, asyncActionControllerFor configuration: RSDAsyncActionConfiguration) -> RSDAsyncActionController? {
        return nil
    }
}
