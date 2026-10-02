extends Node
## Global signal bus for UI/gameplay decoupling. Signals are added as features need them.

@warning_ignore("unused_signal")
signal local_player_spawned(player: Node3D)
@warning_ignore("unused_signal")
signal match_state_changed(state: int)  ## MatchManager.State
@warning_ignore("unused_signal")
signal chat_message(from_name: String, text: String, channel: int)  ## from_name "" = system message
@warning_ignore("unused_signal")
signal plant_alarm_changed(alarm: int)  ## PlantModel.Alarm, clients only
@warning_ignore("unused_signal")
signal local_hazard_hit(text: String)  ## a hazard hit the local player (HUD banner), clients only
@warning_ignore("unused_signal")
signal plant_announcement(text: String)  ## a plant-wide event (SCRAM, coolant) for the HUD banner, clients only
@warning_ignore("unused_signal")
signal feed_event(kind: String, a: String, b: String)  ## a line for the event feed (MatchManager.feed), clients only
