# Audio Manager Implementation

## Overview

The AudioManager is a centralized system for managing all UI sound effects in GodotStation. It provides a clean, static interface for playing sounds throughout the game while maintaining proper volume control and preventing sound spam.

## Features

- **Centralized Sound Management**: Single point of control for all UI audio
- **Volume Control**: Separate volume controls for different sound types
- **Anti-Spam Protection**: Cooldowns prevent sound effects from overlapping
- **Audio Bus Integration**: Uses Godot's audio bus system for proper mixing
- **Static Interface**: Easy to use from any script with `AudioManager.play_ui_click()`

## Sound Categories

### UI Interaction Sounds
- `play_ui_click()` - General button clicks and interactions
- `play_ui_cancel()` - Cancel actions and closing menus
- `play_ui_open_menu()` - Opening menus and panels
- `play_ui_close_menu()` - Closing menus and panels
- `play_ui_menu_selection()` - Menu navigation and selection
- `play_ui_hover()` - Button hover effects

### Item Management Sounds
- `play_ui_equip()` - Equipping items
- `play_ui_unequip()` - Unequipping items
- `play_ui_saved()` - Saving preferences and settings

### System Sounds
- `play_ui_pause()` - Pausing the game
- `play_ui_resume()` - Resuming the game
- `play_ui_exit()` - Exiting menus or the game
- `play_ui_shop()` - Shop interactions
- `play_chat_message()` - New chat messages

## Usage Examples

```gdscript
# In any script, simply call the static methods:
AudioManager.play_ui_click()
AudioManager.play_ui_hover()
AudioManager.play_ui_saved()

# Set volume levels:
AudioManager.set_ui_volume(-5.0)  # Louder
AudioManager.set_ui_volume(-20.0) # Quieter

# Get current volume:
var current_volume = AudioManager.get_ui_volume()
```

## Implementation Details

### Audio Resources
All sound effects are loaded as AudioStream resources from the `res://Sound/UI/` directory:
- SFX_UI_Confirm.ogg
- SFX_UI_Cancel.ogg
- SFX_UI_OpenMenu.ogg
- SFX_UI_CloseMenu.ogg
- SFX_UI_MenuSelections.ogg
- SFX_UI_Equip.ogg
- SFX_UI_Unequip.ogg
- SFX_UI_Saved.ogg
- SFX_UI_Pause.ogg
- SFX_UI_Resume.ogg
- SFX_UI_Exit.ogg
- SFX_UI_Shop.ogg

### Audio Players
The system uses three separate AudioStreamPlayer nodes:
- **UIPlayer**: Main UI interactions and system sounds
- **HoverPlayer**: Button hover effects (lighter volume)
- **SelectionPlayer**: Menu selections with cooldown protection

### Volume Configuration
- UI Volume: -10.0 dB (default)
- Hover Volume: -20.0 dB (quieter for frequent sounds)
- Selection Volume: -15.0 dB (medium volume with cooldown)

### Cooldown Protection
- Hover sounds: 100ms minimum between plays
- Selection sounds: 50ms minimum between plays
- Prevents audio spam during rapid interactions

## Integration Points

### Main Lobby UI (`MainLobbyUI.cs`)
- Button clicks for lobby actions
- Menu navigation
- Chat input interactions

### Inventory System (`InventoryWindow.gd`)
- Opening/closing inventory
- Item selection and management
- Equipment changes

### Preference Menu (`PreferenceMenu.gd`)
- Menu navigation
- Setting changes
- Save/apply actions

### Communications (`Communications.gd`)
- Tab switching
- Chat message notifications
- Admin controls

## Audio Bus Setup

The AudioManager uses Godot's audio bus system:
- **UI Bus (Index 1)**: All UI-related sounds
- **Effects Bus (Index 2)**: General game effects

This allows for separate volume control of UI sounds versus game sounds in the audio mixer.

## Best Practices

1. **Use Appropriate Sounds**: Choose the most relevant sound effect for each action
2. **Avoid Overuse**: Don't add sounds to every minor interaction
3. **Consider Context**: Use quieter sounds for frequent actions
4. **Test Volume Levels**: Ensure sounds are audible but not overwhelming
5. **Respect User Preferences**: The system respects global volume settings

## Future Enhancements

- **3D Positioning**: Add spatial audio for UI elements
- **Dynamic Volume**: Adjust volume based on game state
- **Sound Variations**: Multiple sound variants to prevent repetition
- **Accessibility**: Visual indicators for important audio cues
- **Customization**: Allow users to customize sound effects