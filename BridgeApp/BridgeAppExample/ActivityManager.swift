//
//  ActivityManager.swift
//  BridgeAppExample
//
//  Copyright © 2018-2020 Sage Bionetworks. All rights reserved.
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
import BridgeSDK
import BridgeApp
import Research

public class ActivityManager : NSObject, SBBActivityManagerProtocol {
    
    var schedules = [SBBScheduledActivity]()
    
    var finishedPersistentSchedules: [SBBScheduledActivity] = []
    
    var activityGuidMap : [RSDIdentifier : String] = [:]
    
    let studySetup: StudySetup
    
    let participantManager: ParticipantManager
    
    init(studySetup: StudySetup) {
        self.participantManager = ParticipantManager(studySetup: studySetup)
        self.studySetup = studySetup
        super.init()
    }
    
    func buildSchedules() {
        RSDIdentifier.allTasks.forEach { identifier in
            let resourceName = String(identifier.stringValue.replacingOccurrences(of: " ", with: "_"))
            let taskInfo = SBAActivityInfoObject(identifier: identifier,
                                                  title: identifier.stringValue,
                                                  subtitle: nil,
                                                  detail: nil,
                                                  estimatedMinutes: nil,
                                                  iconImage: nil,
                                                  resource: RSDResourceTransformerObject(resourceName: resourceName),
                                                  moduleId: nil)
            SBABridgeConfiguration.shared.addMapping(with: taskInfo)
            
            let now = Date()
            let startOfDay = now.startOfDay()
            let scheduledOn: Date
            let expiresOn: Date
            
            switch (identifier) {
            case .morning:
                scheduledOn = startOfDay.addingTimeInterval(6 * 3600)
                expiresOn = scheduledOn.addingTimeInterval(4 * 3600)
            case .evening:
                scheduledOn = startOfDay.addingTimeInterval(18 * 3600)
                expiresOn = scheduledOn.addingTimeInterval(4 * 3600)
            default:
                scheduledOn = startOfDay
                expiresOn = startOfDay.addingNumberOfDays(1)
            }
            
            let finishedOn = (studySetup.finishedTasks.contains(identifier) && (scheduledOn <= now))
                ? scheduledOn.addingTimeInterval(60) : nil
            
            schedules.append(createSchedule(with: identifier, scheduledOn: scheduledOn, expiresOn: expiresOn, finishedOn: finishedOn, clientData: nil, schedulePlanGuid: UUID().uuidString))
        }
    }

    public func createSchedule(with identifier: RSDIdentifier, scheduledOn: Date, expiresOn: Date?, finishedOn: Date?, clientData: SBBJSONValue?, schedulePlanGuid: String?) -> SBBScheduledActivity {
        
        let guid = activityGuidMap[identifier] ?? UUID().uuidString
        activityGuidMap[identifier] = guid
        let scheduledOnString = (scheduledOn as NSDate).iso8601StringUTC()!
        let schedule = SBBScheduledActivity(dictionaryRepresentation: [
            "guid" : "\(guid):\(scheduledOnString)",
            "schedulePlanGuid" : schedulePlanGuid ?? UUID().uuidString
            ])!
        schedule.scheduledOn = scheduledOn
        schedule.expiresOn = expiresOn
        schedule.startedOn = finishedOn?.addingTimeInterval(-3 * 60)
        schedule.finishedOn = finishedOn
        schedule.clientData = clientData
        schedule.persistent = NSNumber(value: (expiresOn == nil))

        let dictionary = [
            "activityType" : "task",
            "guid" : guid,
            "label" : identifier.stringValue
        ]
        let activity = SBBActivity(dictionaryRepresentation: dictionary)!
        
        activity.task = SBBTaskReference(dictionaryRepresentation: [ "identifier" : identifier.stringValue ])
        schedule.activity = activity
        
        return schedule
    }
    
    func addFinishedPersistent(_ scheduledActivities: [SBBScheduledActivity]) {
        let filtered = scheduledActivities.filter { $0.persistentValue && $0.isCompleted }
        self.finishedPersistentSchedules.append(contentsOf: filtered)
    }
    
    public let offMainQueue = DispatchQueue(label: "org.sagebionetworks.BridgeApp.TestActivityManager")
    
    public func getScheduledActivities(from scheduledFrom: Date, to scheduledTo: Date, cachingPolicy policy: SBBCachingPolicy, withCompletion completion: @escaping SBBActivityManagerGetCompletionBlock) -> URLSessionTask {
        offMainQueue.async {
            
            // add a new schedule for the finished persistent schedules.
            let newSchedules = self.finishedPersistentSchedules.compactMap { (schedule) -> SBBScheduledActivity? in
                guard let finishedOn = schedule.finishedOn, let activityId = schedule.activityIdentifier else { return nil }
                return self.createSchedule(with: RSDIdentifier(rawValue: activityId),
                                    scheduledOn: finishedOn,
                                    expiresOn: nil,
                                    finishedOn: nil,
                                    clientData: nil,
                                    schedulePlanGuid: schedule.schedulePlanGuid)
            }
            self.schedules.append(contentsOf: newSchedules)
            self.finishedPersistentSchedules.removeAll()
            
            let predicate = SBBScheduledActivity.availablePredicate(from: scheduledFrom, to: scheduledTo)
            let filtered = self.schedules.filter { predicate.evaluate(with: $0) }
            completion(filtered, nil)
        }
        return URLSessionTask()
    }
    
    public func getScheduledActivities(from scheduledFrom: Date, to scheduledTo: Date, withCompletion completion: @escaping SBBActivityManagerGetCompletionBlock) -> URLSessionTask {
        return self.getScheduledActivities(from: scheduledFrom, to: scheduledTo, cachingPolicy: .fallBackToCached, withCompletion: completion)
    }
    
    public func getScheduledActivities(forDaysAhead daysAhead: Int, daysBehind: Int, cachingPolicy policy: SBBCachingPolicy, withCompletion completion: @escaping SBBActivityManagerGetCompletionBlock) -> URLSessionTask {
        fatalError("Deprecated")
    }
    
    public func getScheduledActivities(forDaysAhead daysAhead: Int, cachingPolicy policy: SBBCachingPolicy, withCompletion completion: @escaping SBBActivityManagerGetCompletionBlock) -> URLSessionTask {
        fatalError("Deprecated")
    }
    
    public func getScheduledActivities(forDaysAhead daysAhead: Int, withCompletion completion: @escaping SBBActivityManagerGetCompletionBlock) -> URLSessionTask {
        fatalError("Deprecated")
    }
    
    public func start(_ scheduledActivity: SBBScheduledActivity, asOf startDate: Date, withCompletion completion: SBBActivityManagerUpdateCompletionBlock? = nil) -> URLSessionTask {
        
        offMainQueue.async {
            if let schedule = self.schedules.first(where: { scheduledActivity.guid == $0.guid }) {
                schedule.startedOn = startDate
            } else {
                scheduledActivity.startedOn = startDate
                self.schedules.append(scheduledActivity)
            }
            completion?("passed", nil)
        }
        return URLSessionTask()
    }
    
    public func finish(_ scheduledActivity: SBBScheduledActivity, asOf finishDate: Date, withCompletion completion: SBBActivityManagerUpdateCompletionBlock? = nil) -> URLSessionTask {
        
        offMainQueue.async {
            if let schedule = self.schedules.first(where: { scheduledActivity.guid == $0.guid }) {
                schedule.finishedOn = finishDate
            } else {
                scheduledActivity.finishedOn = finishDate
                self.schedules.append(scheduledActivity)
            }
            self.addFinishedPersistent([scheduledActivity])
            completion?("passed", nil)
        }
        return URLSessionTask()
    }
    
    public func delete(_ scheduledActivity: SBBScheduledActivity, withCompletion completion: SBBActivityManagerUpdateCompletionBlock? = nil) -> URLSessionTask {
        offMainQueue.async {
            self.schedules.remove(where: { scheduledActivity.guid == $0.guid })
            completion?("passed", nil)
        }
        return URLSessionTask()
    }
    
    public func setClientData(_ clientData: SBBJSONValue, for scheduledActivity: SBBScheduledActivity, withCompletion completion: SBBActivityManagerUpdateCompletionBlock? = nil) -> URLSessionTask {
        offMainQueue.async {
            if let schedule = self.schedules.first(where: { scheduledActivity.guid == $0.guid }) {
                schedule.clientData = clientData
            } else {
                scheduledActivity.clientData = clientData
                self.schedules.append(scheduledActivity)
            }
            completion?("passed", nil)
        }
        return URLSessionTask()
    }
    
    public func updateScheduledActivities(_ scheduledActivities: [Any], withCompletion completion: SBBActivityManagerUpdateCompletionBlock? = nil) -> URLSessionTask {
        
        guard let scheduledActivities = scheduledActivities as? [SBBScheduledActivity]
            else {
                fatalError("Objects not of expected cast.")
        }
        
        offMainQueue.async {
            scheduledActivities.forEach { (scheduledActivity) in
                self.schedules.remove(where: { scheduledActivity.guid == $0.guid })
            }
            self.schedules.append(contentsOf: scheduledActivities)
            self.addFinishedPersistent(scheduledActivities)
            completion?("passed", nil)
        }
        return URLSessionTask()
    }
    
    public func getCachedSchedules(using predicate: NSPredicate, sortDescriptors: [NSSortDescriptor]?, fetchLimit: UInt) throws -> [SBBScheduledActivity] {
        
        var results = schedules.filter { predicate.evaluate(with: $0) }
        if let sortDescriptors = sortDescriptors {
            results = (results as NSArray).sortedArray(using: sortDescriptors) as! [SBBScheduledActivity]
        }
        
        return ((fetchLimit > 0) && (fetchLimit < results.count)) ? Array(results[..<Int(fetchLimit)]) : results
    }
}

