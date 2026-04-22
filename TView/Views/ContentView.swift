import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: TViewModel

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            MainView(viewModel: viewModel)
                .tabItem {
                    Label("홈", systemImage: "house.fill")
                }
                .tag(0)
            
            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("설정", systemImage: "gear")
                }
                .tag(1)
        }
        .tint(.blue)
        .preferredColorScheme(viewModel.theme.colorScheme)
    }
}