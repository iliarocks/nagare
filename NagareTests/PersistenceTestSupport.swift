import SwiftData
@testable import Nagare

@MainActor
func orderingRepository(in context: ModelContext) -> SwiftDataNagareRepository {
    SwiftDataNagareRepository(modelContainer: context.container)
}

@MainActor
func orderingCommands(in context: ModelContext) -> NagareDataOrchestrator {
    let repository = orderingRepository(in: context)
    return NagareDataOrchestrator(reader: repository, writer: repository)
}
