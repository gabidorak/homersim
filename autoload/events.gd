extends Node
## Global signal bus for UI/gameplay decoupling. Signals are added as features need them.

@warning_ignore("unused_signal")
signal local_player_spawned(player: Node3D)
@warning_ignore("unused_signal")
signal match_state_changed(state: int)  ## MatchManager.State
@warning_ignore("unused_signal")
signal chat_message(from_name: String, text: String, channel: int)  ## from_name "" = system message
