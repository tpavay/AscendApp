import Foundation
import Testing
@testable import AscendApp

struct SelectedMediaPreparationServiceTests {
    @Test
    func allowsSelectionWithinConfiguredLimits() {
        let validationMessage = SelectedMediaPreparationService.validationMessage(
            forAdditionalMediaCount: 1,
            additionalVideoCount: 0,
            currentMediaCount: 1,
            currentVideoCount: 0
        )

        #expect(validationMessage == nil)
    }

    @Test
    func rejectsSelectionAboveMediaLimit() {
        let validationMessage = SelectedMediaPreparationService.validationMessage(
            forAdditionalMediaCount: 2,
            additionalVideoCount: 0,
            currentMediaCount: 2,
            currentVideoCount: 0
        )

        #expect(validationMessage == "Only 3 combined photos and videos (max 1 video) can be added to a given workout.")
    }

    @Test
    func rejectsSelectionAboveVideoLimit() {
        let validationMessage = SelectedMediaPreparationService.validationMessage(
            forAdditionalMediaCount: 1,
            additionalVideoCount: 1,
            currentMediaCount: 0,
            currentVideoCount: 1
        )

        #expect(validationMessage == "You can only add one video with a max length of 15 seconds.")
    }

    @Test
    func cleanupTemporaryVideoFileRemovesExistingFile() throws {
        let tempURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        let fileContents = Data("temp".utf8)
        try fileContents.write(to: tempURL)

        #expect(FileManager.default.fileExists(atPath: tempURL.path()))

        SelectedMediaPreparationService.cleanupTemporaryVideoFile(at: tempURL)

        #expect(FileManager.default.fileExists(atPath: tempURL.path()) == false)
    }

    @Test
    func cleanupTemporaryVideoFileIgnoresMissingFile() {
        let tempURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")

        SelectedMediaPreparationService.cleanupTemporaryVideoFile(at: tempURL)

        #expect(FileManager.default.fileExists(atPath: tempURL.path()) == false)
    }
}
