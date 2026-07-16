import SwiftUI

struct ProfileSectionHeaderView: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.montserratBold(size: 16))
                .foregroundStyle(.white)
                .tracking(1.4)

            Spacer()

            if let trailing {
                Text(trailing.uppercased())
                    .font(.montserratSemiBold(size: 11))
                    .foregroundStyle(Color.ascendAccent)
                    .tracking(1.2)
            }
        }
        .padding(.horizontal, 2)
    }
}
