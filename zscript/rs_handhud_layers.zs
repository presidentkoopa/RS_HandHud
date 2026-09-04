// RS_HandHUD -- THE LAYERED RENDERER. Ermac's mechanism, ported.
//
// A number is not painted, it is ASSEMBLED: one psprite layer per digit, each
// layer showing a sprite frame chosen by that digit's value. Nothing is drawn
// into a texture, so nothing depends on a canvas existing, opening, surviving
// its plate being hidden, or reaching a model's skin. It asks the engine for
// exactly what every weapon already asks for, which is why his worked and why
// this is here as the second option.
//
// WHAT THE CANVAS RENDERER BUYS AND WHAT IT COSTS. The canvas plates can draw
// bars, icons, a mugshot and free text at any position, and they ride a model
// that can be folded to the wrist. This one draws digits, in rows, and that is
// all it will ever draw. Keep both: rs_handhud_renderer picks.
//
// THE ART IS A ONE-FILE SWAP. Ermac's WH00..WH11 are not in the build we have
// -- zero lumps -- so TEXTURES.txt maps RSHN A..J and RSHY A..J onto the iwad's
// own status-bar digits, which are always present. Point those Patch lines at
// better art and nothing here changes.
//
// FRAME ORDER IS THE LOOKUP. States run A..J for 0..9 in one unbroken run, so
// a digit is FindState("Big") + value. Ermac used a chain of ten A_JumpIfs per
// layer for the same result; this is the same idea with the chain removed.

class RS_HandHUDGlyphs : Inventory
{
	Default
	{
		Inventory.MaxAmount 1;
		Inventory.InterHubAmount 1;
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
		+INVENTORY.QUIET
	}
	States
	{
	Spawn:
		TNT1 A -1;
		Stop;
	// MUST STAY CONTIGUOUS AND IN ORDER -- the handler indexes into this run.
	Big:
		RSHN A -1;
		RSHN B -1;
		RSHN C -1;
		RSHN D -1;
		RSHN E -1;
		RSHN F -1;
		RSHN G -1;
		RSHN H -1;
		RSHN I -1;
		RSHN J -1;
		Stop;
	Small:
		RSHY A -1;
		RSHY B -1;
		RSHY C -1;
		RSHY D -1;
		RSHY E -1;
		RSHY F -1;
		RSHY G -1;
		RSHY H -1;
		RSHY I -1;
		RSHY J -1;
		Stop;
	Blank:
		TNT1 A -1;
		Stop;
	}
}

// =====================================================================
// The layer block. Six glyphs a wrist: three big for the number that
// matters, three small underneath for the one that does not.
//
// Beside the canvas plates (900020/900030) rather than on top of them, so
// both renderers can be up at once while you decide which you want.
// =====================================================================
class RS_HandHUDLayers
{
	const SLOTS  = 6;          // 0..2 big row, 3..5 small row
	const BIGROW = 3;

	const BASE_MAIN =  900100;
	const BASE_OFF  = 1900100;

	clearscope static int LayerOf(int hand, int slot)
	{
		return ((hand == 1) ? BASE_OFF : BASE_MAIN) + slot;
	}
}
