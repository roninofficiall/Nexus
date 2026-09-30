import SwiftUI

struct ContentView: View {

    var body: some View {

        ZStack {

            HandTrackingView()
                .ignoresSafeArea()

            VStack {

                Text("NEXUS")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

            }
            .padding(.top, 30)
        }
    }
}

#Preview {
    ContentView()
}