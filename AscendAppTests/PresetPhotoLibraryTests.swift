import Foundation
import Testing
import UIKit
@testable import AscendApp

/// A photo picked from the full library is decoded at the size a library grid photo loads at,
/// never at the camera's full resolution: the card redraws it on every framing frame and again on
/// export.
struct PresetPhotoLibraryTests {
    private func jpeg(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.6)!
    }

    private func pixelSize(_ image: UIImage) throws -> CGSize {
        let cgImage = try #require(image.cgImage)
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    @Test
    func aLargePickedPhotoIsDecodedWithItsShorterSideAtTheCardBound() async throws {
        let image = try #require(await PresetPhotoLibrary.cardImage(from: jpeg(width: 4_800, height: 3_600)))
        let size = try pixelSize(image)
        #expect(min(size.width, size.height) == PresetPhotoLibrary.cardImageSide)
        #expect(size.width == 2_160, "the photo's aspect ratio was not kept: \(size)")
    }

    @Test
    func aSmallPickedPhotoIsNeverUpscaled() async throws {
        let image = try #require(await PresetPhotoLibrary.cardImage(from: jpeg(width: 800, height: 600)))
        #expect(try pixelSize(image) == CGSize(width: 800, height: 600))
    }

    @Test
    func dataThatIsNotAnImageIsNoPhoto() async {
        #expect(await PresetPhotoLibrary.cardImage(from: Data("not an image".utf8)) == nil)
    }
}
