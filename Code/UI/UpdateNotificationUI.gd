extends Window

@onready var version_label = %VersionLabel
@onready var message_label = %MessageLabel
@onready var progress_bar = %ProgressBar
@onready var download_button = %DownloadButton
@onready var install_button = %InstallButton
@onready var auto_updater = get_node("/root/AutoUpdater")

var new_version: String = ""

func _ready() -> void:
	self.hide()
	self.close_requested.connect(_on_close_pressed)
	if auto_updater:
		auto_updater.connect("UpdateAvailable", Callable(self, "_on_update_available"))
		auto_updater.connect("UpdateDownloadProgress", Callable(self, "_on_download_progress"))
		auto_updater.connect("UpdateReadyToInstall", Callable(self, "_on_ready_to_install"))
		auto_updater.connect("UpdateError", Callable(self, "_on_update_error"))
	else:
		push_error("[UpdateUI] FAILED: AutoUpdater autoload not found at /root/AutoUpdater")

func _on_update_available(version: String) -> void:
	print("[UI] Received signal for version: ", version)
	new_version = version
	
	version_label.text = "New Version: " + version
	message_label.text = "A new version is available! \nLocal: %s -> Remote: %s" % [auto_updater.CurrentVersion, version]
	
	download_button.visible = true
	download_button.disabled = false
	install_button.visible = false
	progress_bar.visible = false
	
	self.show()
	self.popup_centered()
	self.grab_focus()
	self.move_to_foreground()

func show_permission_warning() -> void:
	self.title = "Permissions Required"
	message_label.text = "GodotStation needs Administrator privileges to update files in the current folder. \n\nThe game will restart to request permission."
	download_button.text = "Restart as Admin"
	
	if not download_button.pressed.is_connected(auto_updater.RequestAdminPrivileges):
		download_button.pressed.connect(auto_updater.RequestAdminPrivileges)
	
	self.popup_centered()

func _on_download_progress(progress: float) -> void:
	progress_bar.visible = true
	progress_bar.value = progress * 100
	message_label.text = "Downloading... %d%%" % (progress * 100)

func _on_ready_to_install() -> void:
	message_label.text = "Download complete. Restart to install."
	progress_bar.visible = false
	download_button.visible = false
	install_button.visible = true

func _on_update_error(error: String) -> void:
	message_label.text = "Error: " + error
	progress_bar.visible = false
	download_button.disabled = false

func _on_download_pressed() -> void:
	download_button.disabled = true
	auto_updater.DownloadUpdate()

func _on_install_pressed() -> void:
	auto_updater.RestartToApplyUpdate()

func _on_close_pressed() -> void:
	self.hide()

func initialize_with_data(version: String) -> void:
	print("[UI] initialize_with_data called with:", version)
	_on_update_available(version)

func check_for_updates() -> void:
	auto_updater.CheckForUpdates()
