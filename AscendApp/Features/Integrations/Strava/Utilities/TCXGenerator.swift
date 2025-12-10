//
//  TCXGenerator.swift
//  AscendApp
//
//  Generates TCX (Training Center XML) files for Strava uploads.
//  TCX format allows inclusion of heart rate, calories, and other detailed data.
//

import Foundation

/// Generates TCX file content from workout data
struct TCXGenerator {

    /// Generates a TCX file string from workout data
    /// - Parameters:
    ///   - workout: The workout to export
    ///   - stepHeight: Height per step in meters (for elevation calculation)
    /// - Returns: TCX file content as a string
    static func generate(
        from workout: Workout,
        stepHeightMeters: Double = 0.2032  // Default ~8 inches
    ) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let startTime = workout.date
        let endTime = startTime.addingTimeInterval(workout.duration)

        // Calculate total elevation gain from steps
        let totalElevationMeters = Double(workout.steps) * stepHeightMeters

        // Build trackpoints with heart rate data if available
        let trackpoints = buildTrackpoints(
            workout: workout,
            startTime: startTime,
            dateFormatter: dateFormatter
        )

        // Build the TCX XML
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase
            xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">
          <Activities>
            <Activity Sport="Other">
              <Id>\(dateFormatter.string(from: startTime))</Id>
              <Lap StartTime="\(dateFormatter.string(from: startTime))">
                <TotalTimeSeconds>\(Int(workout.duration))</TotalTimeSeconds>
                <DistanceMeters>\(totalElevationMeters)</DistanceMeters>
        """

        // Add calories if available
        if let calories = workout.caloriesBurned {
            xml += """
                    <Calories>\(calories)</Calories>

            """
        }

        // Add average heart rate if available
        if let avgHR = workout.avgHeartRate {
            xml += """
                    <AverageHeartRateBpm>
                      <Value>\(avgHR)</Value>
                    </AverageHeartRateBpm>

            """
        }

        // Add max heart rate if available
        if let maxHR = workout.maxHeartRate {
            xml += """
                    <MaximumHeartRateBpm>
                      <Value>\(maxHR)</Value>
                    </MaximumHeartRateBpm>

            """
        }

        xml += """
                <Intensity>Active</Intensity>
                <TriggerMethod>Manual</TriggerMethod>
                <Track>
        """

        // Add trackpoints
        xml += trackpoints

        xml += """
                </Track>
              </Lap>
              <Creator xsi:type="Device_t">
                <Name>Ascend App</Name>
                <UnitId>0</UnitId>
                <ProductID>0</ProductID>
              </Creator>
            </Activity>
          </Activities>
          <Author xsi:type="Application_t">
            <Name>Ascend</Name>
            <Build>
              <Version>
                <VersionMajor>1</VersionMajor>
                <VersionMinor>0</VersionMinor>
              </Version>
            </Build>
            <LangID>en</LangID>
          </Author>
        </TrainingCenterDatabase>
        """

        return xml
    }

    /// Builds trackpoint XML elements from workout heart rate data
    private static func buildTrackpoints(
        workout: Workout,
        startTime: Date,
        dateFormatter: ISO8601DateFormatter
    ) -> String {
        let heartRateData = workout.heartRateTimeSeries

        // If we have heart rate time series data, use it
        if !heartRateData.isEmpty {
            return heartRateData.map { dataPoint in
                """
                  <Trackpoint>
                    <Time>\(dateFormatter.string(from: dataPoint.timestamp))</Time>
                    <HeartRateBpm>
                      <Value>\(dataPoint.heartRate)</Value>
                    </HeartRateBpm>
                  </Trackpoint>
                """
            }.joined(separator: "\n")
        }

        // Otherwise, create minimal trackpoints at start and end
        let endTime = startTime.addingTimeInterval(workout.duration)

        var trackpoints = """
              <Trackpoint>
                <Time>\(dateFormatter.string(from: startTime))</Time>
        """

        if let avgHR = workout.avgHeartRate {
            trackpoints += """
                    <HeartRateBpm>
                      <Value>\(avgHR)</Value>
                    </HeartRateBpm>
            """
        }

        trackpoints += """
              </Trackpoint>
              <Trackpoint>
                <Time>\(dateFormatter.string(from: endTime))</Time>
        """

        if let avgHR = workout.avgHeartRate {
            trackpoints += """
                    <HeartRateBpm>
                      <Value>\(avgHR)</Value>
                    </HeartRateBpm>
            """
        }

        trackpoints += """
              </Trackpoint>
        """

        return trackpoints
    }
}
