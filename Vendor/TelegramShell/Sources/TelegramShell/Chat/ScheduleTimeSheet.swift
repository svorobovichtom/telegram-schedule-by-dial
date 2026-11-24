import UIKit

/// "Schedule Message": the sheet Send → hold → Schedule Message opens today. A calendar with the time, a "Repeat" row
/// and a button that says when it will go out.
/// Source: submodules/TelegramUI/Components/ChatScheduleTimeController/Sources/ChatScheduleTimeScreen.swift (title :271,
/// calendar 59 + 6 rows high :357, "Time" and "Repeat" rows 17pt :383/:460, the button 52 high, semibold 17 :574-593).
/// Strings: Conversation.ScheduleMessage.Title / SendToday / SendTomorrow / SendOn, ScheduleMessage.Repeat,
/// ScheduleMessage.RepeatPeriod.Never (Telegram/Telegram-iOS/en.lproj/Localizable.strings:4857-4860, :15441-15442).
/// Here the calendar and time are UIKit's inline date picker.
@MainActor
public final class ScheduleTimeSheet: UIViewController {
    private let theme: Theme
    private let initial: Date
    private let completion: (Date?) -> Void
    private var finished = false

    private let titleLabel = UILabel()
    private let closeButton: GlassButton
    private let picker = UIDatePicker()
    private let repeatRow = UIView()
    private let button = UIButton(type: .system)

    public init(theme: Theme, initial: Date, completion: @escaping (Date?) -> Void) {
        self.theme = theme
        self.initial = initial
        self.completion = completion
        closeButton = GlassButton(icon: UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)))
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.isDark ? UIColor(rgb: 0x1c1c1e) : .white
        titleLabel.text = "Schedule Message"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = theme.controlColor
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)
        closeButton.iconView.tintColor = theme.controlColor
        closeButton.addAction(UIAction { [weak self] _ in self?.finish(nil) }, for: .touchUpInside)
        view.addSubview(closeButton)

        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .inline
        picker.minimumDate = Date().addingTimeInterval(60)
        picker.date = max(initial, picker.minimumDate ?? initial)
        picker.tintColor = theme.sendFill
        picker.addAction(UIAction { [weak self] _ in self?.updateButton() }, for: .valueChanged)
        view.addSubview(picker)

        let repeatTitle = UILabel()
        repeatTitle.text = "Repeat"
        repeatTitle.font = .systemFont(ofSize: 17)
        repeatTitle.textColor = theme.controlColor
        repeatTitle.sizeToFit()
        repeatTitle.frame.origin = CGPoint(x: 0, y: 16)
        repeatRow.addSubview(repeatTitle)
        let never = UILabel()
        never.text = "Never"
        never.font = .systemFont(ofSize: 17)
        never.textColor = theme.controlColor.withAlphaComponent(0.5)
        never.textAlignment = .right
        never.tag = 1
        repeatRow.addSubview(never)
        let separator = UIView()
        separator.backgroundColor = theme.listSeparator
        separator.tag = 2
        repeatRow.addSubview(separator)
        view.addSubview(repeatRow)

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = theme.sendFill
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        button.configuration = config
        button.addAction(UIAction { [weak self] _ in self?.finish(self?.picker.date) }, for: .touchUpInside)
        view.addSubview(button)
        updateButton()

        if let sheet = sheetPresentationController {
            sheet.detents = [.custom { _ in 640 }]
            sheet.prefersGrabberVisible = false
            sheet.preferredCornerRadius = 38
        }
    }

    private func updateButton() {
        let date = picker.date
        let time = Self.time.string(from: date)
        let title: String
        if Calendar.current.isDateInToday(date) {
            title = "Send today at \(time)"
        } else if Calendar.current.isDateInTomorrow(date) {
            title = "Send tomorrow at \(time)"
        } else {
            title = "Send on \(Self.day.string(from: date)) at \(time)"
        }
        button.configuration?.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let side: CGFloat = 16
        closeButton.frame = CGRect(x: side, y: 16, width: 44, height: 44)
        titleLabel.frame = CGRect(x: 70, y: 16, width: width - 140, height: 44)
        let pickerSize = picker.sizeThatFits(CGSize(width: width - 22, height: .greatestFiniteMagnitude))
        picker.frame = CGRect(x: 11, y: 72, width: width - 22, height: pickerSize.height)
        repeatRow.frame = CGRect(x: side + 4, y: picker.frame.maxY, width: width - 2 * (side + 4), height: 52)
        repeatRow.viewWithTag(1)?.frame = CGRect(x: 0, y: 16, width: repeatRow.bounds.width, height: 20)
        repeatRow.viewWithTag(2)?.frame = CGRect(x: 0, y: 0, width: repeatRow.bounds.width, height: 1 / 3)
        let bottom = view.safeAreaInsets.bottom > 0 ? view.safeAreaInsets.bottom : 16
        button.frame = CGRect(x: side, y: view.bounds.height - bottom - 52, width: width - 2 * side, height: 52)
    }

    private func finish(_ date: Date?) {
        guard !finished else { return }
        finished = true
        dismiss(animated: true)
        completion(date)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !finished { finished = true; completion(nil) }
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f
    }()
}
