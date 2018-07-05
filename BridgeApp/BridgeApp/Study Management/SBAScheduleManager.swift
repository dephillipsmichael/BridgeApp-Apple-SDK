//
//  SBAScheduleManager.swift
//  BridgeApp
//
//  Copyright © 2016-2018 Sage Bionetworks. All rights reserved.
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

extension Notification.Name {
    
    /// Notification name posted by the `SBAScheduleManager` when the activities have been updated.
    public static let SBAUpdatedScheduledActivities = Notification.Name(rawValue: "SBAUpdatedScheduledActivities")
    
    /// Notification name posted by the `SBAScheduleManager` before the manager will send an update
    /// of the scheduled activities to Bridge.
    public static let SBAWillSendUpdatedScheduledActivities = Notification.Name(rawValue: "SBAWillSendUpdatedScheduledActivities")
    
    /// Notification name posted by the `SBAScheduleManager` after the manager did send an update
    /// of the scheduled activities to Bridge.
    public static let SBADidSendUpdatedScheduledActivities = Notification.Name(rawValue: "SBADidSendUpdatedScheduledActivities")
}

/// Default data source handler for scheduled activities. This manager is used to get `SBBScheduledActivity`
/// objects and upload the task results for Bridge services. By default, this manager will fetch all the
/// activities, but will *not* cache them all in memory. Instead, it will filter out those activites that are
/// valid for today and the most recent finished activity (if any) for each activity identifier where the
/// "activity identifier" refers to an `SBBActivity` object's associated `SBAActivityReference`.
///
open class SBAScheduleManager: NSObject, RSDDataArchiveManager, RSDTrackingDelegate {

    /// List of keys used in the notifications sent by this manager.
    public enum NotificationKey : String {
        case previousActivities, updatedActivities, updateScheduleGuids
    }
    
    /// Pointer to the shared configuration to use.
    public var configuration: SBABridgeConfiguration {
        return SBABridgeConfiguration.shared
    }
    
    /// Pointer to the shared activity manager to use.
    public var activityManager: SBBActivityManagerProtocol {
        return BridgeSDK.activityManager
    }
    
    public override init() {
        super.init()
        
        // Add an observer that the schedules have been updated from the server.
        NotificationCenter.default.addObserver(forName: .SBAFinishedUpdatingScheduleCache, object: nil, queue: .main) { (notification) in
            self.reloadData()
        }
        
        // Add an observer that a schedule manager has updated the scheduled activities. Often updating the
        // schedules will change the available "next" schedule.
        NotificationCenter.default.addObserver(forName: .SBAWillSendUpdatedScheduledActivities, object: nil, queue: .main) { (notification) in
            if let schedules = notification.userInfo?[SBAScheduleManager.NotificationKey.updatedActivities] as? [SBBScheduledActivity] {
                self.willSendUpdatedSchedules(for: schedules)
            }
        }
        
        // load the activities from cache on init.
        self.loadScheduledActivities()
    }
    
    
    // MARK: Data source
    
    /// Add an identifier that can be used for mapping this schedule manager to the displayed schedules.
    open var identifier : String = "Today"

    /// This is an array of the activities fetched by the call to the server in `reloadData`. By default,
    /// this list includes the activities filtered using the `scheduleFilterPredicate`.
    @objc open var scheduledActivities: [SBBScheduledActivity] = []
    
    // MARK: Schedule loading and filtering
    
    /// The activity group associated with this schedule manager. If non-nil, this will be used in setting up
    /// the filtering predicates and finding the "most appropriate" schedule when creating a task path.
    /// This will get the activity group by getting the currently registered activity group from the shared
    /// configuration using `self.identifier` as the group identifier.
    open var activityGroup : SBAActivityGroup? {
        get {
            return self.configuration.activityGroup(with: self.identifier)
        }
        set {
            guard let newGroup = newValue else { return }
            if self.configuration.activityGroup(with: newGroup.identifier) == nil {
                self.configuration.addMapping(with: newGroup)
            }
            self.identifier = newGroup.identifier
        }
    }
    
    /// Fetch request objects can be used to make compound fetch requests to retrieve schedules that match
    /// different sets of parameters. For example, a task group might be set up to group a set of tasks
    /// together where the schedule used to run a new task is different from the schedule used to mark it as
    /// finished. This allows for that more complicated logic.
    public struct FetchRequest {
        
        /// The predicate to use to filter the fetched results.
        public let predicate: NSPredicate
        
        /// The sort descriptors to use to sort the results.
        public let sortDescriptors: [NSSortDescriptor]?
        
        /// The maximum number of schedules to fetch in this request.
        public let fetchLimit: UInt?
        
        public init(predicate: NSPredicate, sortDescriptors: [NSSortDescriptor]?, fetchLimit: UInt?) {
            self.predicate = predicate
            self.sortDescriptors = sortDescriptors
            self.fetchLimit = fetchLimit
        }
    }
    
    /// The fetch requests to use to fetch the schedules associated with this manager. By default, if
    /// this schedule manager has an associated activity group, then this will return an array of the
    /// fetch requests for those schedules available today and the most recently finished schedule for each
    /// activity included in the group. Otherwise, a request will be created for all activities available
    /// today.
    open func fetchRequests() -> [FetchRequest] {
        if let group = activityGroup {
            
            // Default filtering if there is an associated activity group is to return the current schedules
            // (the ones that are valid *now*) and the most recent finished schedule (to allow for marking
            // the activity as "completed".
            
            // Get today's schedules.
            var requests: [FetchRequest] = []
            let todayPredicate = NSCompoundPredicate(andPredicateWithSubpredicates:
                    [self.availablePredicate(),
                     SBBScheduledActivity.activityGroupPredicate(for: group)])
            let todayRequest = FetchRequest(predicate: todayPredicate, sortDescriptors: nil, fetchLimit: nil)
            requests.append(todayRequest)
            
            // Add a request **for each** identifier to get the most recently finished schedule even if that
            // schedule is *not* part of this activity group.
            group.activityIdentifiers.forEach {
                let predicate = self.historyPredicate(for: $0)
                let sortDescriptors = [SBBScheduledActivity.finishedOnSortDescriptor(ascending: false)]
                requests.append(FetchRequest(predicate: predicate, sortDescriptors: sortDescriptors, fetchLimit: 1))
            }
            
            return requests
        }
        else {
            
            // If there is no activity group associated with this schedule then return all activities that
            // are valid today.
            return [FetchRequest(predicate: self.availablePredicate(), sortDescriptors: nil, fetchLimit: nil)]
        }
    }
    
    /// The predicate to use for filtering today's activities for those available today. If there is an
    /// `activityGroup` associated with this schedule manager, the fetch request for today's activities will
    /// be built using this predicate and the activity group predicate. Otherwise, only this predicate will
    /// be used. Default is to return `SBBScheduledActivity.availableTodayPredicate()`.
    open func availablePredicate() -> NSPredicate {
        return SBBScheduledActivity.availableTodayPredicate()
    }
    
    /// The predicate to use for filtering past activities. By default, this will return all activities where
    /// the `finishedOn` property is non-nil and the activity identifier matches the given value.
    /// - parameter activityIdentifier: The activity identifier for the schedule.
    /// - returns: The predicate for this fetch request.
    open func historyPredicate(for activityIdentifier: RSDIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates:
            [SBBScheduledActivity.isFinishedPredicate(),
             SBBScheduledActivity.activityIdentifierPredicate(with: activityIdentifier.stringValue)])
    }
    
    /// State management for whether or not the schedules are reloading.
    public private(set) var isReloading: Bool = false
    
    /// A serial queue used to manage data crunching.
    public let offMainQueue = DispatchQueue(label: "org.sagebionetworks.BridgeApp.SBAScheduleManager")
    
    /// Reload the data by fetching changes to the scheduled activities.
    open func reloadData() {
        loadScheduledActivities()
    }
    
    /// Load the scheduled activities from cache using the `fetchRequests()` for this schedule manager.
    public final func loadScheduledActivities() {
        DispatchQueue.main.async {
            if self.isReloading { return }
            self.isReloading = true
            
            self.offMainQueue.async {
                do {
                
                    // Fetch the cached schedules.
                    let requests = self.fetchRequests()
                    var scheduleMap: [String : SBBScheduledActivity] = [:]
                    
                    try requests.forEach {
                        let fetchedSchedules = try self.getCachedSchedules(using: $0)
                        fetchedSchedules.forEach {
                            scheduleMap[$0.guid] = $0
                        }
                    }
                    let schedules: [SBBScheduledActivity] = scheduleMap.values.map { $0 }
                    //print("\n---\(self.identifier):\n\(schedules)")

                    DispatchQueue.main.async {
                        self.update(fetchedActivities: schedules)
                        self.isReloading = false
                    }
                }
                catch let error {
                    DispatchQueue.main.async {
                        self.updateFailed(error)
                        self.isReloading = false
                    }
                }
            }
        }
    }
    
    /// Add internal method for testing.
    internal func getCachedSchedules(using fetchRequest: FetchRequest) throws -> [SBBScheduledActivity] {
        return try self.activityManager.getCachedSchedules(using: fetchRequest.predicate,
                                                                sortDescriptors: fetchRequest.sortDescriptors,
                                                                fetchLimit: fetchRequest.fetchLimit ?? 0)
    }

    
    // MARK: Data handling
    
    /// Called on the main thread if updating the scheduled activities fails.
    open func updateFailed(_ error: Error) {
        debugPrint("WARNING: Failed to fetch cached schedules: \(error)")
    }
    
    /// Called on the main thread once Bridge returns the requested scheduled activities.
    ///
    /// - parameter fetchedActivities: The list of activities returned by the service.
    open func update(fetchedActivities: [SBBScheduledActivity]) {
        //print("\n\n--- Update called for \(self.identifier) with:\n\(fetchedActivities)")
        if (fetchedActivities != self.scheduledActivities) {
            self.scheduledActivities = fetchedActivities
            let previous = self.scheduledActivities
            self.didUpdateScheduledActivities(from: previous)
        }
    }
    
    /// Called on the main thread before sending the given schedules to the server for update. The default
    /// implementation will call `self.update(fetchedActivities:)` on a unioned set of the updated schedules
    /// and the schedules that are currently in memory. This method will filter the schedules using the
    /// `fetchedRequests()` for this manager, but will not use the fetch limit parameter to limit the number
    /// of schedules returned.
    ///
    /// - parameter schedules: The schedules that will be updated.
    open func willSendUpdatedSchedules(for schedules:[SBBScheduledActivity]) {
        let mergedSet = self.scheduledActivities.sba_union(with: schedules, where: { $0.guid == $1.guid })
        let filters = self.fetchRequests().map { $0.predicate }
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: filters)
        let updatedSchedules = mergedSet.filter { predicate.evaluate(with: $0) }
        self.update(fetchedActivities: updatedSchedules)
    }
    
    /// Called when the schedules have changed.
    ///
    /// - parameter previousActivities: The schedules that were previously being stored in memory.
    open func didUpdateScheduledActivities(from previousActivities: [SBBScheduledActivity]) {
        
        // Post notification that the schedules were updated.
        NotificationCenter.default.post(name: .SBAUpdatedScheduledActivities,
                                        object: self,
                                        userInfo: [NotificationKey.previousActivities: previousActivities])
    }
    
    /// Sort the scheduled activities. By default this will sort by comparing the `scheduledOn` property.
    open func sortActivities(_ scheduledActivities: [SBBScheduledActivity]?) -> [SBBScheduledActivity]? {
        guard (scheduledActivities?.count ?? 0) > 0 else { return nil }
        return scheduledActivities!.sorted(by: { (scheduleA, scheduleB) -> Bool in
            return scheduleA.scheduledOn.compare(scheduleB.scheduledOn) == .orderedAscending
        })
    }
    
    
    // MARK: Schedule management
    
    /// If a schedule is unavailable, then the user is shown an alert explaining when it will become
    /// available.
    ///
    /// - parameter schedule: The schedule to check.
    /// - returns: The message to display in an alert for a schedule that is not currently available.
    open func messageForUnavailableSchedule(_ schedule: SBBScheduledActivity) -> String {
        var scheduledTime: String!
        if schedule.scheduledOn < Date().startOfDay().addingNumberOfDays(1) {
            scheduledTime = schedule.scheduledTime
        }
        else {
            scheduledTime = DateFormatter.localizedString(from: schedule.scheduledOn, dateStyle: .medium, timeStyle: .none)
        }
        return Localization.localizedStringWithFormatKey("ACTIVITY_SCHEDULE_MESSAGE_%@", scheduledTime)
    }
    
    /// Get the schema info associated with the given activity identifier. By default, this looks at the
    /// shared bridge configuration's schema reference map.
    open func schemaInfo(for activityIdentifier: String) -> RSDSchemaInfo? {
        return self.configuration.schemaInfo(for: activityIdentifier)
    }
    
    /// Get the scheduled activity that is associated with this schedule identifier and task result.
    ///
    /// For the case where this is a combo task that includes multiple schemas (for example, medication
    /// tracking and finger tapping) then we want to preference the schedule associated with the **schema**
    /// over the schedule that was used to trigger the task. The default behavior of this method, therefore
    /// is to look for a schema and return the schedule associated with that schema, if found.
    ///
    /// - parameters:
    ///     - taskResult: The task result for this task, subtask, or section.
    ///     - scheduleIdentifier: The schedule identifier that was used to start the task.
    /// - returns: The schedule associated with this task view controller (if found).
    open func scheduledActivity(for taskResult: RSDTaskResult, scheduleIdentifier: String?) -> SBBScheduledActivity? {
        
        let todayPredicate = SBBScheduledActivity.availableTodayPredicate()
        
        // Look for a schedule that matches the given scheduleIdentifier.
        let guidSchedule: SBBScheduledActivity? = {
            guard let scheduleGuid = scheduleIdentifier else { return nil }
            if let schedule = self.scheduledActivities.first(where: { $0.guid == scheduleGuid }) {
                return schedule
            }
            else {
                let activityGuid = SBBScheduledActivity.activityGuid(from: scheduleGuid)
                return self.scheduledActivities.rsd_last(where: {
                    $0.activity.guid == activityGuid && todayPredicate.evaluate(with: $0)
                })
            }
        }()
        
        // We only care about task results that have a matching schema otherwise, return the guid schedule.
        guard let schema = taskResult.schemaInfo ?? schemaInfo(for: taskResult.identifier),
            let _ = schema.schemaIdentifier else {
                return guidSchedule
        }
        
        // Look for a schedule that matches the given schema identifier.
        let taskIdentifier = taskResult.identifier
        let taskSchedule = self.scheduledActivities.rsd_last(where: {
            $0.activityIdentifier == taskIdentifier &&
            todayPredicate.evaluate(with: $0)
        })
        
        // If the found schema-based schedule has the same activity guid as the guid-based schedule,
        // then return the guid schedule.
        if taskSchedule == nil || taskSchedule!.activity.guid == guidSchedule?.activity.guid {
            return guidSchedule
        }
        else {
            return taskSchedule
        }
    }
    
    /// Is the given task info completed for the given date?
    open func isCompleted(for taskInfo: RSDTaskInfo, on date: Date) -> Bool {
        let taskPredicate = SBBScheduledActivity.activityIdentifierPredicate(with: taskInfo.identifier)
        let finishedPredicate = SBBScheduledActivity.finishedOnDatePredicate(on: date)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [taskPredicate, finishedPredicate])
        return self.scheduledActivities.first(where: { predicate.evaluate(with: $0) }) != nil
    }
    
    /// Get the scheduled activities associated with a given group that are available on a given day.
    /// The criteria for determining availablity is dependent upon the timing of the activity. For a
    /// day in the past, the criteria includes when the task was finished, expired, and scheduled. For
    /// a day in the future, the criterion is decided by when the activity is scheduled. For today, the
    /// activity must either be finished today, or available today (scheduled for a time window that
    /// includes this day.
    ///
    /// - parameters:
    ///     - activityGroup: The activity group to filter on.
    ///     - availableOn: The date for the day when the activities are "available".
    /// - returns: The schedule associated with this task view controller (if available).
    open func scheduledActivities(for activityGroup: SBAActivityGroup, availableOn: Date) -> [SBBScheduledActivity] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates:
            [SBBScheduledActivity.availableOnPredicate(on: availableOn),
             SBBScheduledActivity.activityGroupPredicate(for: activityGroup)])
        return self.scheduledActivities.filter { predicate.evaluate(with: $0) }
    }
    
    /// Instantiate a task path appropriate to the given task info. This method will attempt to map the
    /// task info to a schedule, but if called, it is assumed that even if there is no schedule associated
    /// with this task, that the task path should be instantiated.
    ///
    /// The returned result includes the instantiated task path and the reference schedule (if found).
    ///
    /// - note: This method should not be used to instantiate child task paths that are used to track the
    /// task state for a subtask. Instead, it is intended for starting a new task and will set up any state
    /// handling (such as tracking data groups) that must be managed globally.
    ///
    /// - parameters:
    ///     - taskInfo: The task info object to use to create the task path.
    ///     - activityGroup: The activity group to use to determine the schedule. This is used for the case
    ///                      where there may be multiple schedules with the same task and the
    ///                      `schedulePlanGUID` on the activity group is used to determine which available
    ///                      schedule is the one to associate with this task.
    /// - returns:
    ///     - taskPath: The instantiated task path.
    ///     - referenceSchedule: The schedule to reference for uploading the task path results (if any).
    open func instantiateTaskPath(for taskInfo: RSDTaskInfo, in activityGroup: SBAActivityGroup? = nil) -> (taskPath: RSDTaskPath, referenceSchedule: SBBScheduledActivity?) {
        let schedule = scheduledActivity(for: taskInfo.identifier, in: activityGroup)
        let taskPath: RSDTaskPath = configuration.instantiateTaskPath(for: taskInfo, using: schedule)
        setupTaskPath(taskPath, with: schedule)
        return (taskPath, schedule)
    }
    
    /// Instantiate a task path appropriate to the given task. This method will attempt to map the
    /// task to a schedule, but if called, it is assumed that even if there is no schedule associated
    /// with this task, that the task path should be instantiated.
    ///
    /// The returned result includes the instantiated task path and the reference schedule (if found).
    ///
    /// - note: This method should not be used to instantiate child task paths that are used to track the
    /// task state for a subtask. Instead, it is intended for starting a new task and will set up any state
    /// handling (such as tracking data groups) that must be managed globally.
    ///
    /// - parameters:
    ///     - task: The task object to use to create the task path.
    ///     - activityGroup: The activity group to use to determine the schedule. This is used for the case
    ///                      where there may be multiple schedules with the same task and the
    ///                      `schedulePlanGUID` on the activity group is used to determine which available
    ///                      schedule is the one to associate with this task.
    /// - returns:
    ///     - taskPath: The instantiated task path.
    ///     - referenceSchedule: The schedule to reference for uploading the task path results (if any).
    open func instantiateTaskPath(for task: RSDTask, in activityGroup: SBAActivityGroup? = nil) -> (taskPath: RSDTaskPath, referenceSchedule: SBBScheduledActivity?) {
        let schedule = scheduledActivity(for: task.identifier, in: activityGroup)
        let taskPath: RSDTaskPath = RSDTaskPath(task: task)
        setupTaskPath(taskPath, with: schedule)
        return (taskPath, schedule)
    }
    
    /// Instantiate a task path appropriate to the given schedule.
    ///
    /// - note: This method should not be used to instantiate child task paths that are used to track the
    /// task state for a subtask. Instead, it is intended for starting a new task and will set up any state
    /// handling (such as tracking data groups) that must be managed globally.
    ///
    /// - parameter schedule: The schedule to use to set up the task.
    /// - returns: The instantiated task path.
    open func instantiateTaskPath(for schedule: SBBScheduledActivity) -> RSDTaskPath {
        let taskPath = schedule.instantiateTaskPath()
        setupTaskPath(taskPath, with: schedule)
        return taskPath
    }
    
    func scheduledActivity(for taskIdentifier: String, in activityGroup: SBAActivityGroup?) -> SBBScheduledActivity? {
        // Set up predicates.
        var taskPredicate = SBBScheduledActivity.activityIdentifierPredicate(with: taskIdentifier)
        if let group = (activityGroup ?? self.activityGroup) {
            if let guid = group.activityGuidMap?[taskIdentifier] {
                taskPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    taskPredicate, SBBScheduledActivity.activityGuidPredicate(with: guid)])
            }
            else if let guid = group.schedulePlanGuid {
                taskPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    taskPredicate, SBBScheduledActivity.schedulePlanPredicate(with: guid)])
            }
        }
        
        // Get the schedule.
        let todaySchedules = self.scheduledActivities.filter {
            taskPredicate.evaluate(with: $0) && (($0.scheduledOn.timeIntervalSinceNow < 0) && !$0.isExpired)
        }
        let schedule = todaySchedules.rsd_last(where: { $0.isCompleted == false }) ?? todaySchedules.last
        
        return schedule
    }
    
    func setupTaskPath(_ taskPath: RSDTaskPath, with schedule: SBBScheduledActivity?) {
        
        // Assign values to the task path from the schedule.
        taskPath.scheduleIdentifier = schedule?.guid
        taskPath.trackingDelegate = self
        
        // Set up the data groups tracking rule.
        if let participant = SBAParticipantManager.shared.studyParticipant {
            // If there is an existing tracking rule then there was a task that wasn't
            // saved. So these changes should **not** be commited. Throw them out.
            SBAFactory.shared.trackingRules.remove(where: { $0 is DataGroupsTrackingRule})
            let rule = DataGroupsTrackingRule(initialCohorts: participant.dataGroups ?? [])
            SBAFactory.shared.trackingRules.append(rule)
        } else {
            debugPrint("WARNING: Missing a study particpant. Cannot get the data groups.")
        }
    }
    
    /// Find the most recent client data appended to any schedule for this activity identifier.
    ///
    /// - parameter activityIdentifier: The activity identifier for the client data associated with this task.
    /// - returns: The client data JSON (if any) associated with this activity identifier.
    open func clientData(with activityIdentifier: String) -> SBBJSONValue? {
        // Get the clientData from the most recent finished schedule with the same activity identifier.
        var clientData: SBBJSONValue?
        var currentFinishedOn = Date.distantPast
        let activityPredicate = SBBScheduledActivity.activityIdentifierPredicate(with: activityIdentifier)
        self.scheduledActivities.forEach { (schedule) in
            if let data = schedule.clientData,
                let finishedOn = schedule.finishedOn, finishedOn > currentFinishedOn,
                activityPredicate.evaluate(with: schedule) {
                clientData = data
                currentFinishedOn = finishedOn
            }
        }
        return clientData
    }
    
    /// Subclass the cohorts tracking rule so that we can use casting to check for an existing
    /// tracking rule.
    class DataGroupsTrackingRule : RSDCohortTrackingRule {
    }
    
    // MARK: RSDTaskViewControllerDelegate
    
    /// Call from the view controller that is used to display the task when the task is finished.
    ///
    /// - note: This method does not dismiss the task.
    open func taskController(_ taskController: RSDTaskController, didFinishWith reason: RSDTaskFinishReason, error: Error?) {
        if reason != .completed {
            // If the task finished with an error or discarded results, then delete the output directory.
            taskController.taskPath.deleteOutputDirectory()
            if let err = error {
                debugPrint("WARNING! Task failed: \(err)")
            }
        }
    }
    
    /// Call from the view controller that is used to display the task when the task is ready to save.
    open func taskController(_ taskController: RSDTaskController, readyToSave taskPath: RSDTaskPath) {
        
        // Update the schedule on the server but only if the survey was not ended early. In that case, only
        // send the archive but do not mark the task as finished or update the data groups.
        if !taskPath.didExitEarly {
            self.offMainQueue.async {
                self.updateDataGroups(for: taskPath)
                self.updateSchedules(for: taskPath)
                self.archiveAndUpload(taskPath: taskPath)
            }
        }
        else {
            self.archiveAndUpload(taskPath: taskPath)
        }
    }
    
    /// Do nothing.
    open func taskController(_ taskController: RSDTaskController, asyncActionControllerFor configuration: RSDAsyncActionConfiguration) -> RSDAsyncActionController? {
        return nil
    }
    
    // MARK: Upload to server
    
    /// Update the data groups. By default, this will look for changes on the shared `DataGroupsTrackingRule`.
    ///
    /// - parameter taskPath: The task path for the task which has just run.
    open func updateDataGroups(for taskPath: RSDTaskPath) {
        let rules = SBAFactory.shared.trackingRules.remove(where: { $0 is DataGroupsTrackingRule})
        guard let rule = rules.first as? DataGroupsTrackingRule,
            rule.initialCohorts != rule.currentCohorts
            else {
                return
        }
        
        BridgeSDK.participantManager.updateDataGroups(withGroups: rule.currentCohorts) { (_, error) in
            if let err = error {
                debugPrint("WARNING! Failed to update the data groups: \(err)")
            }
        }
    }
    
    /// Update the values on the scheduled activity. By default, this will recurse through the task path
    /// and its children, looking for a schedule associated with the subtask path.
    ///
    /// - parameter taskPath: The task path for the task which has just run.
    public func updateSchedules(for taskPath: RSDTaskPath) {
        guard taskPath.parentPath == nil else {
            assertionFailure("This method should **only** be called for the top-level task path.")
            return
        }
        
        // Recursively get and update all the schedules in this task path.
        var schedules = [SBBScheduledActivity]()
        func appendSchedule(for path: RSDTaskPath) {
            if let schedule = self.getAndUpdateSchedule(for: path) {
                schedules.append(schedule)
            }
            path.childPaths.enumerated().forEach {
                appendSchedule(for: $0.element.value)
            }
        }
        appendSchedule(for: taskPath)

        // Send message to server that the scheduled activites were updated.
        self.sendUpdated(for: schedules, taskPath: taskPath)
    }
    
    /// For each schedule that this task modifies, mark it as completed and add the client data.
    ///
    /// - parameter taskPath: The task path for the task which has just run.
    open func getAndUpdateSchedule(for taskPath: RSDTaskPath) -> SBBScheduledActivity? {
        guard let schedule = self.scheduledActivity(for: taskPath.result, scheduleIdentifier: taskPath.scheduleIdentifier)
            else {
                return nil
        }
        
        schedule.startedOn = taskPath.result.startDate
        schedule.finishedOn = taskPath.result.endDate
        self.appendClientData(from: taskPath, to: schedule)
        
        return schedule
    }
    
    /// Append the client data to the schedule.
    ///
    /// - parameters:
    ///     - taskPath: The task path for the task which has just run.
    ///     - schedule: The schedule associated with this task segment.
    open func appendClientData(from taskPath: RSDTaskPath, to schedule: SBBScheduledActivity) {
        guard let (clientData, shouldReplace) = self.buildClientData(from: taskPath, for: schedule) else { return }
        if !shouldReplace, let existingClientData = schedule.clientData {
            
            // If there is previous client data, then append this to that object.
            var array: [Any] = (existingClientData as? [Any]) ?? [existingClientData]
            if let newArray = clientData as? [Any] {
                array.append(contentsOf: newArray)
            } else {
                array.append(clientData)
            }
            schedule.clientData = array as NSArray
        }
        else {

            // If there isn't previous client data or the previous data should be replaced, then set the
            // client data to either an array or dictionary (the allowed top-level JSON objects).
            schedule.clientData = {
                if let array = clientData as? NSArray {
                    return array
                }
                else if shouldReplace, let dictionary = clientData as? NSDictionary {
                    return dictionary
                }
                else {
                    return [clientData] as NSArray
                }
            }()
        }
    }
    
    /// Build the client data from the given task path.
    ///
    /// - parameters:
    ///     - taskPath: The task path for the task which has just run.
    ///     - schedule: The schedule associated with this task segment.
    /// - returns: The client data built for this task path (if any).
    open func buildClientData(from taskPath: RSDTaskPath, for schedule: SBBScheduledActivity) -> (clientData: SBBJSONValue, shouldReplacePrevious: Bool)? {
        do {
            let clientData = try recursiveGetClientData(from: taskPath.result, isTopLevel: true)
            if clientData != nil {
                return clientData
            }
            else {
                let answerMap = self.buildSurveyAnswerMap(from: taskPath, for: schedule)
                if answerMap.count > 0 {
                    return (answerMap as NSDictionary, true)
                }
                else {
                    return nil
                }
            }
        }
        catch let err {
            assertionFailure("Failed to encode client data: \(err)")
            return nil
        }
    }
    
    /// Build a simple answer map for this task result.
    /// - note: This can be used to create client data for surveys.
    open func buildSurveyAnswerMap(from taskPath: RSDTaskPath, for schedule: SBBScheduledActivity) -> [String : Any] {
        let taskResult = taskPath.result
        var answers = [String : Any]()
        
        func appendValue(_ value: Any?, forKey key: String) {
            answers[key] = (value as? SBBJSONValue) ?? (value as? RSDJSONValue)?.jsonObject()
        }
        
        func appendResult(_ result: RSDResult) {
            if let answers = (result as? RSDCollectionResult)?.answers() {
                answers.forEach {
                    appendValue($0.value, forKey: $0.key)
                }
            }
            else if let answerResult = result as? RSDAnswerResult {
                appendValue(answerResult.value, forKey: answerResult.identifier)
            }
        }
        
        taskResult.stepHistory.forEach { appendResult($0) }
        taskResult.asyncResults?.forEach { appendResult($0) }
        
        return answers
    }
    
    private func recursiveGetClientData(from taskResult: RSDTaskResult, isTopLevel: Bool) throws  -> (SBBJSONValue, Bool)? {
        // Verify that this task result is not associated with a different schema.
        guard isTopLevel || (taskResult.schemaInfo ?? self.schemaInfo(for: taskResult.identifier) == nil)
            else {
                return nil
        }
        
        var dataResults: [SBBJSONValue] = []
        var shouldReplacePrevious = false
        if let (data, shouldReplace) = try recursiveGetClientData(from: taskResult.stepHistory) {
            dataResults.append(data)
            shouldReplacePrevious = shouldReplace || shouldReplacePrevious
        }
        if let asyncResults = taskResult.asyncResults,
            let (data, shouldReplace) = try recursiveGetClientData(from: asyncResults) {
            dataResults.append(data)
            shouldReplacePrevious = shouldReplace || shouldReplacePrevious

        }
        
        if let clientData = dataResults.count <= 1 ? dataResults.first : (dataResults as NSArray) {
            return (clientData, shouldReplacePrevious)
        }
        else {
            return nil
        }
    }
    
    private func recursiveGetClientData(from results: [RSDResult]) throws -> (SBBJSONValue, Bool)? {
        
        func getClientData(_ result: RSDResult) throws -> (SBBJSONValue, Bool)? {
            if let clientResult = result as? SBAClientDataResult,
                let clientData = try clientResult.clientData() {
                return (clientData, clientResult.shouldReplacePreviousClientData())
            }
            else if let taskResult = result as? RSDTaskResult {
                return try self.recursiveGetClientData(from: taskResult, isTopLevel: false)
            }
            else if let collectionResult = result as? RSDCollectionResult {
                return try self.recursiveGetClientData(from: collectionResult.inputResults)
            }
            else {
                return nil
            }
        }
        
        var shouldReplacePrevious: Bool = false
        let dictionary = try results.rsd_filteredDictionary { (result) throws -> (String, SBBJSONValue)? in
            guard let (data, shouldReplace) = try getClientData(result) else { return nil }
            shouldReplacePrevious = shouldReplace || shouldReplacePrevious
            return (result.identifier, data)
        }
        
        // Return the "most appropriate" value for the combined results.
        if dictionary.count == 0 {
            return nil
        }
        else if dictionary.sba_uniqueCount() == 1 || shouldReplacePrevious {
            return (dictionary.first!.value, shouldReplacePrevious)
        }
        else {
            return (dictionary as NSDictionary, false)
        }
    }
    
    /// Send message to Bridge server to update the given schedules. This includes both the task
    /// that was completed and any tasks that were performed as a requirement of completion of the
    /// primary task (such as a required one-time survey).
    ///
    /// - parameters:
    ///     - schedules: The schedules for which to send updates.
    ///     - taskPath: The task path (if available) for the task run that triggered this update.
    open func sendUpdated(for schedules: [SBBScheduledActivity], taskPath: RSDTaskPath? = nil) {
        
        // Copy the schedule objects to ensure that these changes
        let guids = schedules.map { $0.guid }
        
        // Post notification that the schedules were updated.
        NotificationCenter.default.post(name: .SBAWillSendUpdatedScheduledActivities,
                                        object: self,
                                        userInfo: [NotificationKey.updatedActivities : schedules])
        
        self.activityManager.updateScheduledActivities(schedules) { (_, _) in
            // Post notification that the schedules were updated.
            NotificationCenter.default.post(name: .SBADidSendUpdatedScheduledActivities,
                                            object: self,
                                            userInfo: [NotificationKey.updateScheduleGuids : guids])
        }
    }
    
    /// Archive and upload results.
    ///
    /// DO NOT MAKE OPEN. This method retains the task path until archiving is completed and because it
    /// nils out the pointer to the task path with a strong reference to `self`, it will also retain the
    /// schedule manager until the completion block is called. syoung 05/31/2018
    private final func archiveAndUpload(taskPath: RSDTaskPath) {
        let uuid = UUID()
        self._retainedPaths[uuid] = taskPath
        taskPath.archiveResults(with: self) {
            self._retainedPaths[uuid] = nil
        }
    }
    private var _retainedPaths: [UUID : RSDTaskPath] = [:]
    
    // MARK: RSDDataArchiveManager
    
    /// Should the task result archiving be continued if there was an error adding data to the current
    /// archive? Default behavior is to flush the archive and then return `false`.
    ///
    /// - parameters:
    ///     - archive: The current archive being built.
    ///     - error: The encoding error that was thrown.
    /// - returns: Whether or not archiving should continue. Default = `false`.
    open func shouldContinueOnFail(for archive: RSDDataArchive, error: Error) -> Bool {
        debugPrint("ERROR! Failed to archive results: \(error)")
        // Flush the archive.
        (archive as? SBBDataArchive)?.remove()
        return false
    }
    
    /// When archiving a task result, it is possible that the results of a task need to be split into
    /// multiple archives -- for example, when combining two or more activities within the same task. If the
    /// task result components should be added to the current archive, then the manager should return
    /// `currentArchive` as the response. If the task result *for this section* should be ignored, then the
    /// manager should return `nil`. This allows the application to only upload data that is needed by the
    /// study, and not include information that is ignored by *this* study, but may be of interest to other
    /// researchers using the same task protocol.
    open func dataArchiver(for taskResult: RSDTaskResult, scheduleIdentifier: String?, currentArchive: RSDDataArchive?) -> RSDDataArchive? {

        // Look for a schema info associated with this portion of the task result. If not found, then
        // return the current archive.
        let schema = taskResult.schemaInfo ?? self.schemaInfo(for: taskResult.identifier)
        guard (currentArchive == nil) || (schema != nil) else {
            return currentArchive
        }
        
        
        let schemaInfo = schema ?? RSDSchemaInfoObject(identifier: taskResult.identifier, revision: 1)
        let archiveIdentifier = schemaInfo.schemaIdentifier ?? taskResult.identifier
        let schedule = self.scheduledActivity(for: taskResult, scheduleIdentifier: scheduleIdentifier)
            ?? (currentArchive as? SBAScheduledActivityArchive)?.schedule
        let isPlaceholder = (currentArchive == nil) && (schema == nil) && (schedule == nil)
        
        // If there is a top-level archive then return the exisiting if and only if the identifiers are the
        // same or the schema is nil.
        if let inputArchive = currentArchive,
            ((inputArchive.identifier == archiveIdentifier) || (schema == nil)) {
            return inputArchive
        }
        
        // Otherwise, instantiate a new archive.
        return SBAScheduledActivityArchive(identifier: archiveIdentifier, schemaInfo: schemaInfo, schedule: schedule, isPlaceholder: isPlaceholder)
    }
    
    /// Finalize the upload of all the created archives.
    public func encryptAndUpload(taskPath: RSDTaskPath, dataArchives: [RSDDataArchive], completion: @escaping (() -> Void)) {
        #if DEBUG
        dataArchives.forEach {
            guard let archive = $0 as? SBAScheduledActivityArchive else { return }
            self.copyTestArchive(archive: archive)
        }
        #endif
        let archives: [SBBDataArchive] = dataArchives.compactMap {
            guard let archive = $0 as? SBBDataArchive else { return nil }
            return !archive.isEmpty() ? archive : nil
        }
        SBBDataArchive.encryptAndUploadArchives(archives)
        completion()
    }
    
    /// By default, if an archive fails, the error is printed and that's all that is done.
    open func handleArchiveFailure(taskPath: RSDTaskPath, error: Error, completion: @escaping (() -> Void)) {
        debugPrint("WARNING! Failed to archive \(taskPath.identifier). \(error)")
        completion()
    }
    
    #if DEBUG
    private func copyTestArchive(archive: SBAScheduledActivityArchive) {
        guard SBAParticipantManager.shared.isTestUser else { return }
        do {
            if !archive.isCompleted {
                try archive.complete()
            }
            let fileManager = FileManager.default
            
            let outputDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dirURL = outputDirectory.appendingPathComponent("archives", isDirectory: true)
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
            
            // Scrub non-alphanumeric characters from the identifer
            var characterSet = CharacterSet.alphanumerics
            characterSet.invert()
            var filename = archive.identifier
            while let range = filename.rangeOfCharacter(from: characterSet) {
                filename.removeSubrange(range)
            }
            filename.append("-")
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HHmm"
            let dateString = dateFormatter.string(from: Date())
            filename.append(dateString)
            let debugURL = dirURL.appendingPathComponent(filename, isDirectory: false).appendingPathExtension("zip")
            try fileManager.copyItem(at: archive.unencryptedURL, to: debugURL)
            debugPrint("Copied archive to \(debugURL)")
            
        } catch let err {
            debugPrint("Failed to copy archive: \(err)")
        }
    }
    #endif
}
