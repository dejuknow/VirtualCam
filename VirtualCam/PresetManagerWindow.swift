import Cocoa

class PresetManagerWindow: NSWindow {
    private let presetManager = PresetManager.shared
    private var tableView: NSTableView!
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        title = "Manage Presets"
        setupUI()
    }
    
    private func setupUI() {
        let scrollView = NSScrollView(frame: contentView!.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        
        tableView = NSTableView()
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        
        scrollView.documentView = tableView
        contentView?.addSubview(scrollView)
        
        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        
        let addButton = NSButton(title: "Add", target: self, action: #selector(addPreset))
        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removePreset))
        
        buttonStack.addArrangedSubview(addButton)
        buttonStack.addArrangedSubview(removeButton)
        
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(buttonStack)
        
        NSLayoutConstraint.activate([
            buttonStack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 20),
            buttonStack.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -8)
        ])
    }
    
    @objc private func addPreset() {
        let newPreset = Preset(
            name: "New Preset",
            type: .none,
            settings: BackgroundSettings()
        )
        presetManager.addPreset(newPreset)
        tableView.reloadData()
    }
    
    @objc private func removePreset() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 else { return }
        
        presetManager.removePreset(at: selectedRow)
        tableView.reloadData()
    }
}

extension PresetManagerWindow: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return presetManager.presets.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let preset = presetManager.presets[row]
        let cell = NSTableCellView()
        let textField = NSTextField(labelWithString: preset.name)
        cell.addSubview(textField)
        textField.frame = cell.bounds
        textField.autoresizingMask = [.width, .height]
        return cell
    }
}
