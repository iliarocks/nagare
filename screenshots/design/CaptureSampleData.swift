// Injected only into the temporary capture workspace by prepare_capture.py.
if arguments.contains("--capture-app-store") {
    for project in try context.fetch(FetchDescriptor<Project>()) { context.delete(project) }
    for todo in try context.fetch(FetchDescriptor<Todo>()) { context.delete(todo) }
    for event in try context.fetch(FetchDescriptor<Event>()) { context.delete(event) }
    for template in try context.fetch(FetchDescriptor<RecurrenceTemplate>()) { context.delete(template) }
    let calendar = Calendar.autoupdatingCurrent
    let today = calendar.startOfDay(for: .now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
    let friday = calendar.date(byAdding: .day, value: 2, to: today)!
    let project = Project(title: "Weekend away", notes: "A few days by the coast.", isPriority: true, order: "i")
    context.insert(project)
    let home = Project(title: "Around the house", order: "i")
    context.insert(home)
    func task(_ title: String, day: Date, order: String, projectOrder: String? = nil, notes: String? = nil) {
        let todo = Todo(title: title, notes: notes, scheduledDate: day, order: order, projectOrder: projectOrder)
        context.insert(todo)
        if projectOrder != nil { todo.project = project }
    }
    task("Book the train", day: today, order: "9", projectOrder: "9")
    task("Pick up groceries", day: today, order: "i")
    task("Call Alex", day: today, order: "r")
    let lunch = calendar.date(bySettingHour: 12, minute: 30, second: 0, of: today)!
    context.insert(Todo(title: "Lunch with Maya", scheduledDate: lunch, includesTime: true, endDate: lunch.addingTimeInterval(3600), order: "w"))
    task("Choose a place to stay", day: tomorrow, order: "9", projectOrder: "i", notes: "Somewhere near the coast.\n\nCheck the last train on Sunday.\nAsk about leaving bags after checkout.")
    task("Pick up the camera", day: tomorrow, order: "i")
    task("Find a walking route", day: tomorrow, order: "r", projectOrder: "r")
    task("Pack a book", day: friday, order: "9", projectOrder: "w")
    task("Water the plants", day: friday, order: "i")
    try SwiftDataTransaction.save(context)
    return
}
