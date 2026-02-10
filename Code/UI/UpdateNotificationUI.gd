extends Control

# References to UI elements
@onready var update_panel: Panel
@onready var version_label: Label
@onready var message_label: Label
@onready var progress_bar: ProgressBar
@onready var download_button: Button
@onready var install_button: Button
@onready var close_button: Button
@onready var auto_updater: AutoUpdater

var new_version: String = ""

func _ready() -> void:
	# Get reference to AutoUpdater
	auto_updater = get_node_or_null("/root/AutoUpdater")
	
	if auto_updater == null:
		push_error("[UpdateUI] AutoUpdater not found!")
		return
	
	# Connect to AutoUpdater signals
	auto_updater.update_available.connect(_on_update_available)
	auto_updater.update_download_progress.connect(_on_download_progress)
	auto_updater.update_ready_to_install.connect(_on_ready_to_install)
	auto_updater.update_error.connect(_on_update_error)
	
	# Setup UI elements (you'll need to create these in the scene)
	update_panel = get_node_or_null("UpdatePanel")
	version_label = get_node_or_null("UpdatePanel/VBoxContainer/VersionLabel")
	message_label = get_node_or_null("UpdatePanel/VBoxContainer/MessageLabel")
	progress_bar = get_node_or_null("UpdatePanel/VBoxContainer/ProgressBar")
	download_button = get_node_or_null("UpdatePanel/VBoxContainer/HBoxContainer/DownloadButton")
	install_button = get_node_or_null("UpdatePanel/VBoxContainer/HBoxContainer/InstallButton")
	close_button = get_node_or_null("UpdatePanel/VBoxContainer/HBoxContainer/CloseButton")
	
	# Connect button signals
	if download_button:
		download_button.pressed.connect(_on_download_pressed)
	if install_button:
		install_button.pressed.connect(_on_install_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	
	# Hide UI initially
	if update_panel:
		update_panel.visible = false
	if progress_bar:
		progress_bar.visible = false
	if install_button:
		install_button.visible = false

func _on_update_available(version: String) -> void:
	new_version = version
	
	if update_panel:
		update_panel.visible = true
	
	if version_label:
		version_label.text = "New Version Available: %s" % version
	
	if message_label:
		message_label.text = "A new version of GodotStation is available!\nCurrent version: %s" % auto_updater.CurrentVersion
	
	if download_button:
		download_button.visible = true
		download_button.disabled = false
	
	print("[UpdateUI] Update available: ", version)

func _on_download_progress(progress: float) -> void:
	if progress_bar:
		progress_bar.visible = true
		progress_bar.value = progress * 100
	
	if message_label:
		message_label.text = "Downloading update... %d%%" % (progress * 100)

func _on_ready_to_install() -> void:
	if message_label:
		message_label.text = "Update downloaded! Restart the game to install."
	
	if progress_bar:
		progress_bar.visible = false
	
	if download_button:
		download_button.visible = false
	
	if install_button:
		install_button.visible = true
		install_button.disabled = false
	
	print("[UpdateUI] Update ready to install")

func _on_update_error(error: String) -> void:
	if message_label:
		message_label.text = "Update Error: %s" % error
	
	if progress_bar:
		progress_bar.visible = false
	
	if download_button:
		download_button.disabled = false
	
	push_error("[UpdateUI] Update error: " + error)

func _on_download_pressed() -> void:
	if download_button:
		download_button.disabled = true
	
	if message_label:
		message_label.text = "Preparing download..."
	
	auto_updater.DownloadUpdate()

func _on_install_pressed() -> void:
	# Restart the game to apply the update
	auto_updater.RestartToApplyUpdate()

func _on_close_pressed() -> void:
	if update_panel:
		update_panel.visible = false

# Manual check for updates (can be called from settings menu)
func check_for_updates() -> void:
	if message_label:
		message_label.text = "Checking for updates..."
	
	if update_panel:
		update_panel.visible = true
	
	auto_updater.CheckForUpdates()
