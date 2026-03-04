extends Node

# Corporate Theater — GameState (Autoload Singleton)
# Single source of truth for all persistent player state.
# Persists to disk. Emits signals consumed by all systems.

signal clue_added(clue: Dictionary)
signal contact_unlocked(contact_id: String)
signal browser_navigate(url: String, article_id: String)
signal note_added(note: Dictionary)

const SAVE_PATH := "user://save.json"

# ── State ─────────────────────────────────────────────────────────────────────

var discovered_clues: Array[String] = []
var unlocked_contacts: Array[String] = ["elena_vasquez"]
var conversation_states: Dictionary = {}       # contact_id -> last conv id
var message_history: Dictionary = {}           # contact_id -> Array of {from, text}
var notes: Array[Dictionary] = []              # auto-populated evidence log
var browser_history: Array[String] = []
var visited_articles: Array[String] = []

# ── Clue Registry — defines what each clue_id means ──────────────────────────

const CLUE_DEFINITIONS: Dictionary = {
	"clue_clearsky_partnership": {
		"title": "ClosedAI + Project Clear Sky",
		"category": "organizations",
		"summary": "ClosedAI publicly announced a partnership with the government's Project Clear Sky initiative. Framed as public safety infrastructure.",
		"source": "Z Feed / @ClosedAI",
		"severity": "medium"
	},
	"clue_unity_accord_threat": {
		"title": "The Unity Accord — Veiled Threat",
		"category": "patterns",
		"summary": "Maxwell Holt posted about companies that 'declined' the Unity Accord. Three companies declined. All three collapsed within months. The post reads as a warning in hindsight.",
		"source": "Z Feed / @maxwellholt_cai",
		"severity": "high"
	},
	"clue_data_collection_lie": {
		"title": "ClosedAI Data Policy — Public vs Reality",
		"category": "evidence",
		"summary": "ClosedAI PR claims they don't collect data beyond 'strictly necessary.' ToS Section 14 grants them perpetual irrevocable rights to all outputs and behavioral data.",
		"source": "Z Feed / @ClosedAI_Press",
		"severity": "high"
	},
	"clue_media_narrative_control": {
		"title": "Media Narrative — Synchronized Coverage",
		"category": "patterns",
		"summary": "Every major outlet ran nearly identical framing on the Safety Compact signing. Same quotes, same angle, same timing. Coordinated or coincidence.",
		"source": "CNX Tech",
		"severity": "medium"
	},
	"clue_clearsky_depth": {
		"title": "Project Clear Sky — Deeper Than Stated",
		"category": "organizations",
		"summary": "Maxwell Holt personally thanked Project Clear Sky on Z. The gratitude feels disproportionate for a routine infrastructure partnership.",
		"source": "Z Feed / @maxwellholt_cai",
		"severity": "medium"
	},
	"clue_marcus_tull": {
		"title": "Marcus Tull — Former Horizon Architect",
		"category": "contacts",
		"summary": "Elena Vasquez identified Marcus Tull as a former systems architect on Project Horizon. He left ClosedAI abruptly 8 months ago. Handle: @m_tull_builds.",
		"source": "Z Messenger / Elena V.",
		"severity": "critical"
	},
	"clue_priya_nair": {
		"title": "Priya Nair — Silenced Engineer",
		"category": "contacts",
		"summary": "Senior engineer who filed an internal safety concern and was removed. Signed an NDA exit agreement with financial settlement. Z account deactivated same day.",
		"source": "Z Messenger / Elena V.",
		"severity": "high"
	},
	"clue_priya_contact": {
		"title": "Priya Nair — Contact Method",
		"category": "contacts",
		"summary": "Encrypted email: p.nair.personal@protonmail.com — provided by Elena. May have evidence of what she reported internally.",
		"source": "Z Messenger / Elena V.",
		"severity": "critical"
	},
	"clue_api_endpoint": {
		"title": "ClosedAI Legacy API Endpoint",
		"category": "technical",
		"summary": "Unsecured legacy endpoint on closedai-pub.net: /api/v1/research/shared — Elena confirmed it was not fully deprecated. Possible entry point.",
		"source": "Z Messenger / Elena V.",
		"severity": "critical"
	},
	"clue_horizon_profile": {
		"title": "Horizon Target Profile — Evidence",
		"category": "evidence",
		"summary": "Marcus Tull sent a screenshot of a Horizon target profile. Name redacted. Behavioral tag: 'Category 7 — Narrative Threat (Organic).' Applied to journalists who find truth independently.",
		"source": "Z Messenger / Marcus T.",
		"severity": "critical"
	},
	"clue_elena_report_incoming": {
		"title": "Elena's Safety Report — In Transit",
		"category": "evidence",
		"summary": "Elena Vasquez printed her 12-page internal safety report before deleting the digital copy. She is photographing it and smuggling it out of the building.",
		"source": "Z Messenger / Elena V.",
		"severity": "high"
	},
	"clue_vertex_collapse": {
		"title": "Vertex Mind Bankruptcy — Pattern",
		"category": "patterns",
		"summary": "Vertex Mind filed Chapter 11 months after declining the Safety Compact. CEO Sandra Okafor stated they were 'systematically excluded' from government contracts. Two other holdouts also collapsed.",
		"source": "CNX Tech",
		"severity": "high"
	},
	"clue_horizon_internal_name": {
		"title": "Project Horizon — Internal Codename",
		"category": "technical",
		"summary": "Anonymous Redit post from a ClosedAI employee names the Clear Sky team as 'Horizon' internally. Contract ID: CAI-GOV-0091-HS. Amount: classified.",
		"source": "Redit / throwaway_cai_emp",
		"severity": "critical"
	},
	"clue_veil_model": {
		"title": "VEIL — Undisclosed Language Model",
		"category": "technical",
		"summary": "DarkPulse document names an internal model called VEIL — not the same as the commercial product. Used by Horizon for generating targeted behavioral influence content.",
		"source": "DarkPulse / Anonymous",
		"severity": "critical"
	},
	"clue_soft_stabilization": {
		"title": "Soft Stabilization — Government Terminology",
		"category": "evidence",
		"summary": "The government refers to Horizon's influence operations as 'soft stabilization.' ClosedAI internally calls it 'prosocial infrastructure.' Both are euphemisms for behavioral manipulation.",
		"source": "DarkPulse / Anonymous",
		"severity": "critical"
	}
}

const CATEGORIES: Array[String] = ["evidence", "contacts", "organizations", "technical", "patterns"]

const CATEGORY_LABELS: Dictionary = {
	"evidence": "EVIDENCE",
	"contacts": "CONTACTS",
	"organizations": "ORGANIZATIONS",
	"technical": "TECHNICAL",
	"patterns": "PATTERNS"
}

const SEVERITY_COLORS: Dictionary = {
	"low": "#666688",
	"medium": "#cc9933",
	"high": "#cc4422",
	"critical": "#ff2244"
}


# ── Save / Load ───────────────────────────────────────────────────────────────

func save() -> void:
	var data := {
		"discovered_clues": discovered_clues,
		"unlocked_contacts": unlocked_contacts,
		"conversation_states": conversation_states,
		"message_history": message_history,
		"notes": notes,
		"browser_history": browser_history,
		"visited_articles": visited_articles
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	discovered_clues = _to_string_array(data.get("discovered_clues", []))
	unlocked_contacts = _to_string_array(data.get("unlocked_contacts", ["elena_vasquez"]))
	conversation_states = data.get("conversation_states", {})
	message_history = data.get("message_history", {})
	notes = data.get("notes", [])
	browser_history = _to_string_array(data.get("browser_history", []))
	visited_articles = _to_string_array(data.get("visited_articles", []))


func new_game() -> void:
	discovered_clues = []
	unlocked_contacts = ["elena_vasquez"]
	conversation_states = {}
	message_history = {}
	notes = []
	browser_history = []
	visited_articles = []
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


# ── Clue System ───────────────────────────────────────────────────────────────

func discover_clue(clue_id: String) -> void:
	if clue_id in discovered_clues:
		return
	discovered_clues.append(clue_id)

	var def: Dictionary = CLUE_DEFINITIONS.get(clue_id, {})
	if def.is_empty():
		return

	var note := {
		"clue_id": clue_id,
		"title": def.get("title", clue_id),
		"category": def.get("category", "evidence"),
		"summary": def.get("summary", ""),
		"source": def.get("source", "unknown"),
		"severity": def.get("severity", "low"),
		"timestamp": Time.get_datetime_string_from_system()
	}
	notes.append(note)
	emit_signal("clue_added", note)
	emit_signal("note_added", note)
	save()


func unlock_contact(contact_id: String) -> void:
	if contact_id in unlocked_contacts:
		return
	unlocked_contacts.append(contact_id)
	emit_signal("contact_unlocked", contact_id)
	save()


# ── Messenger State ───────────────────────────────────────────────────────────

func save_conversation_state(contact_id: String, conv_id: String) -> void:
	conversation_states[contact_id] = conv_id
	save()


func append_message(contact_id: String, from: String, text: String) -> void:
	if not message_history.has(contact_id):
		message_history[contact_id] = []
	message_history[contact_id].append({"from": from, "text": text})
	save()


func get_messages(contact_id: String) -> Array:
	return message_history.get(contact_id, [])


func get_conversation_state(contact_id: String) -> String:
	return conversation_states.get(contact_id, "")


# ── Browser ───────────────────────────────────────────────────────────────────

func navigate_browser(url: String, article_id: String = "") -> void:
	if url not in browser_history:
		browser_history.append(url)
	emit_signal("browser_navigate", url, article_id)
	save()


func mark_article_visited(article_id: String) -> void:
	if article_id not in visited_articles:
		visited_articles.append(article_id)
		save()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _to_string_array(arr: Array) -> Array[String]:
	var result: Array[String] = []
	for item in arr:
		result.append(str(item))
	return result
