// RS_HandHUD -- READOUTS STUCK TO THINGS THAT MOVE.
//
// Four of them, and they are the same object four times: a flat plate on its
// own psprite layer, skinned with a canvas this file paints.
//
//   main wrist / off wrist    what you are carrying, and how you are doing
//   main gun / off gun        the same numbers, on the gun itself
//
// A WRIST READOUT AND AN ON-GUN READOUT ARE ONE PROBLEM, not two. Both are
// "stick a readout to a thing that moves", and the only difference is which
// layer the plate rides and what it says. Ermac's RLVR built them as two
// separate systems welded into his weapon base class -- ten psprite layers for
// the wristwatch, seven more for the gun -- and could only ever read his own
// guns. RS_WeaponWheel's on-gun tag went the other way and placed a world
// billboard at a hand-measured offset PER WEAPON, which is why it never
// worked. This is one table with four rows.
//
// ---------------------------------------------------------------------------
// PLACEMENT IS THE ENGINE'S JOB, NOT THIS FILE'S.
//
// MODELDEF's `PlacementCVars <prefix>` makes the renderer read
// <prefix>_ofs_x/_ofs_y/_ofs_z, _yaw/_pitch/_roll, _scale and _scale_x/y/z
// for that model every frame (r_data/models.cpp). Every slider is read by the
// engine directly and nothing here touches position at all. RS_Grenade's held
// prop already works this way.
//
// The alternative was psprite bone ANCHORING (AnchorLayer/AnchorBone), which
// this file used at first. It works, but it needs a NAMED BONE on the target
// model -- the engine tests `AnchorLayer >= 0 && AnchorBone != NAME_None` --
// and only IQM carries bones. Almost every weapon model in a Doom mod is MD3,
// which has none, so the gun mounts could never have worked that way.
// PlacementCVars needs nothing from the model it rides.
//
// ---------------------------------------------------------------------------
// THE FOUR RULES OF DRAWING ON A CANVAS, learned the hard way in one day and
// encoded in RS_HandHUDCanvas so no caller can get them wrong again:
//
//   1. NO DRAW TAGS ON TEXT. Canvas.DrawText takes the same vararg tag list
//      as DrawTexture but rejects most of them, and an invalid tag is a VM
//      ABORT, not a warning. DTA_ScaleX killed the paint mid-way: the bed had
//      been drawn and nothing after it ever was, which reads in a headset as
//      a black plate with a rim and nothing else. Size comes from the font
//      and the canvas, never from a tag.
//   2. A CANVAS SAMPLES BOTTOM-UP. Author top-down and convert once, at the
//      boundary. The wheel's card faces document the same thing.
//   3. THE SKIN STAYS IN MODELDEF. A_ChangeModel rebinds the model on the
//      actor instance, and these plates do not resolve their model that way
//      -- they go through BaseSpriteModelFrames, which is why the class needs
//      +DECOUPLEDANIMATIONS and MODELDEF uses BaseFrame. Rebinding took that
//      lookup out from under them and the plates vanished entirely.
//   4. NOTHING OUTSIDE RS_HandHUDCanvas TOUCHES A Canvas. One class, a small
//      API, all four rules inside it.
//
// ---------------------------------------------------------------------------
// SCOPES. WorldTick (play) owns the layers, the gate and the numbers; it
// cannot reach the status bar. UiTick (ui) owns the painting and can. The play
// side changes the world, the ui side only draws -- which is why the ui side
// never writes anything the play side reads.

// =====================================================================
// The plate actors. One class per mount because MODELDEF binds per class,
// and that is the only reason they differ.
// =====================================================================
class RS_HandHUDPlate : Inventory
{
	Default
	{
		Inventory.MaxAmount 1;
		Inventory.InterHubAmount 1;
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
		+INVENTORY.QUIET
		// REQUIRED. With a TNT1 Spawn state there is no FrameIndex for the
		// model lookup to hit, so the psprite resolves its model through
		// BaseSpriteModelFrames (MODELDEF BaseFrame) -- and that path is only
		// consulted for a +DECOUPLEDANIMATIONS actor. Without the flag the
		// layer falls through to the sprite path and draws nothing at all.
		// RS_HandIdle and RR_AmmoInHand carry it for the same reason.
		+DECOUPLEDANIMATIONS
	}
	States
	{
	Spawn:
		TNT1 A -1;
		Stop;
	}
}
class RS_HandHUDPlateM  : RS_HandHUDPlate {}   // main wrist
// The strap rides its own layer under the dial, so it can be switched off
// alone and so tinting the dial does not drag the strap with it.
class RS_HandHUDBeltM   : RS_HandHUDPlate {}
class RS_HandHUDBeltO   : RS_HandHUDPlate {}
class RS_HandHUDPlateO  : RS_HandHUDPlate {}   // off wrist
class RS_HandHUDPlateGM : RS_HandHUDPlate {}   // main gun
class RS_HandHUDPlateGO : RS_HandHUDPlate {}   // off gun

// =====================================================================
// THE MOUNT TABLE. Everything that distinguishes one readout from another,
// in one place. A fifth readout is a fifth row here plus a MODELDEF block.
// =====================================================================
class RS_HandHUDMount
{
	const COUNT = 4;

	const M_WRIST_MAIN = 0;
	const M_WRIST_OFF  = 1;
	const M_GUN_MAIN   = 2;
	const M_GUN_OFF    = 3;

	// Beside the hands (900000) and the reload's in-hand magazine (900010).
	// The 1900000 range is what puts a layer on the OFF controller.
	clearscope static int LayerOf(int m)
	{
		switch (m)
		{
		case M_WRIST_MAIN: return  900020;
		case M_WRIST_OFF:  return 1900020;
		case M_GUN_MAIN:   return  900030;
		case M_GUN_OFF:    return 1900030;
		}
		return 900020;
	}

	clearscope static int HandOf(int m)
	{
		return (m == M_WRIST_OFF || m == M_GUN_OFF) ? 1 : 0;
	}

	clearscope static bool IsGun(int m)
	{
		return m == M_GUN_MAIN || m == M_GUN_OFF;
	}

	clearscope static Name ClassOf(int m)
	{
		switch (m)
		{
		case M_WRIST_MAIN: return 'RS_HandHUDPlateM';
		case M_WRIST_OFF:  return 'RS_HandHUDPlateO';
		case M_GUN_MAIN:   return 'RS_HandHUDPlateGM';
		case M_GUN_OFF:    return 'RS_HandHUDPlateGO';
		}
		return 'RS_HandHUDPlateM';
	}

	// Must match the canvastexture lines in ANIMDEFS and the Skin lines in
	// MODELDEF.
	clearscope static String CanvasOf(int m)
	{
		switch (m)
		{
		case M_WRIST_MAIN: return "RSHUDMAIN";
		case M_WRIST_OFF:  return "RSHUDOFF";
		case M_GUN_MAIN:   return "RSHUDGUNM";
		case M_GUN_OFF:    return "RSHUDGUNO";
		}
		return "RSHUDMAIN";
	}

	// The cvar prefix, SHARED WITH MODELDEF's PlacementCVars line -- so
	// <prefix>_ofs_x and friends are read by the ENGINE, and <prefix>_on,
	// <prefix>_role and <prefix>_roll by this file.
	clearscope static String PrefixOf(int m)
	{
		switch (m)
		{
		case M_WRIST_MAIN: return "rs_hh_m";
		case M_WRIST_OFF:  return "rs_hh_o";
		case M_GUN_MAIN:   return "rs_hh_gm";
		case M_GUN_OFF:    return "rs_hh_go";
		}
		return "rs_hh_m";
	}

	clearscope static String NameOf(int m)
	{
		switch (m)
		{
		case M_WRIST_MAIN: return "main wrist";
		case M_WRIST_OFF:  return "off wrist";
		case M_GUN_MAIN:   return "main gun";
		case M_GUN_OFF:    return "off gun";
		}
		return "?";
	}
}

// What a plate says. A role is a question; the painter decides how to answer
// it in the space available.
class RS_HandHUDRole
{
	const AMMO   = 0;   // loaded / capacity, reserve
	const VITALS = 1;   // mugshot, health, armour, keys
	const BOTH   = 2;   // vitals across the plate, ammo in the right panel
}

// =====================================================================
// THE ONLY CLASS ALLOWED TO TOUCH A CANVAS.
//
// Panel-aware: a plate is three columns wide whether or not the mesh is
// folded, so the same content lands sensibly on the flat quad and on the
// bracer. Panel 0 is left, 1 centre, 2 right; PANEL_ALL spans them.
// =====================================================================
class RS_HandHUDCanvas ui
{
	const W = 128;      // must match the canvastexture lines in ANIMDEFS
	const H = 64;

	const PANEL_ALL = -1;

	private Canvas c;

	// RULE 2, in one place: a canvas samples bottom-up, so everything is
	// authored top-down and converted here and nowhere else.
	private int fy(int yTop, int height) { return H - (yTop + height); }

	private int panelX(int panel)
	{
		if (panel <= PANEL_ALL) return 0;
		return (W / 3) * clamp(panel, 0, 2);
	}
	private int panelW(int panel)
	{
		if (panel <= PANEL_ALL) return W;
		return W / 3;
	}

	// Open a canvas and lay the bed. False when the canvas texture is not
	// declared, so the caller draws nothing rather than guessing.
	bool Begin(String name)
	{
		c = TexMan.GetCanvas(name);
		if (!c) return false;

		// Translucent, the way the wheel declares its card faces. Without
		// this the plate composites as an opaque slab.
		TexMan.SetCanvasTextureTranslucent(name, true);
		c.Clear(0, 0, W, H, Color(255, 10, 11, 13));
		c.DrawLineFrame(Color(255, 90, 96, 104), 1, 1, W - 2, H - 2, 1);
		return true;
	}

	// RULE 1: no tags, ever. Anything that wants bigger text picks a bigger
	// font or a smaller canvas.
	void Text(Font f, int col, int panel, int xIn, int yTop, String s)
	{
		if (!c || !f || s.Length() == 0) return;
		c.DrawText(f, col, panelX(panel) + xIn, fy(yTop, f.GetHeight()), s);
	}

	void TextCentred(Font f, int col, int panel, int yTop, String s)
	{
		if (!c || !f || s.Length() == 0) return;
		int x = panelX(panel) + (panelW(panel) - f.StringWidth(s)) / 2;
		c.DrawText(f, col, x, fy(yTop, f.GetHeight()), s);
	}

	// Textures keep DTA_DestWidth/DestHeight, which the wheel already proves
	// on this engine's canvases; it was only the text tags that aborted.
	void Icon(TextureID t, int panel, int xIn, int yTop, int w, int h)
	{
		if (!c || !t.IsValid()) return;
		c.DrawTexture(t, false, panelX(panel) + xIn, fy(yTop, h),
			DTA_DestWidth, w, DTA_DestHeight, h, DTA_FlipY, true);
	}

	// frac 0..1. Two Clears rather than a texture, so it needs no art.
	void Bar(int panel, int xIn, int yTop, int w, int h, double frac, Color fill)
	{
		if (!c) return;
		int x = panelX(panel) + xIn;
		int y = fy(yTop, h);
		c.Clear(x, y, x + w, y + h, Color(255, 26, 28, 32));
		int fw = int(w * clamp(frac, 0.0, 1.0));
		if (fw > 0) c.Clear(x, y, x + fw, y + h, fill);
	}

	// A KNOWN PATTERN, for answering "is ANY of this reaching the plate".
	// Three coloured bars and a digit per panel: if the plate shows this and
	// not the readout, the fault is in what the readout was given -- not in
	// the canvas, the skin, the model, the layer or the placement.
	void SelfTest(Font f)
	{
		if (!c) return;
		Bar(0, 4, 6, panelW(0) - 8, 12, 1.0, Color(255, 220,  60,  60));
		Bar(1, 4, 6, panelW(1) - 8, 12, 1.0, Color(255,  60, 220,  60));
		Bar(2, 4, 6, panelW(2) - 8, 12, 1.0, Color(255,  60, 120, 240));
		TextCentred(f, Font.CR_UNTRANSLATED, 0, 26, "1");
		TextCentred(f, Font.CR_UNTRANSLATED, 1, 26, "2");
		TextCentred(f, Font.CR_UNTRANSLATED, 2, 26, "3");
	}
}

// =====================================================================
// THE HANDLER.
// =====================================================================
class RS_HandHUD : EventHandler
{
	// ---- play state, read by the painter ---------------------------------
	private bool mUp[4];            // the layer is currently installed

	private int  mWepLoaded;        // -1: no magazine split, show the pool
	private int  mWepCap;
	private int  mWepPool;
	private bool mWepDry;
	private bool mWepNone;

	private int  mHealth;
	private int  mArmor;
	private TextureID mArmorIcon;
	private Array<TextureID> mKeyIcons;

	private int mSigAmmo;
	private int mSigVit;

	// ---- ui state --------------------------------------------------------
	private ui int mPaints;         // paints attempted, for the debug line

	// ---- cvar shorthand --------------------------------------------------
	clearscope static double Num(String n, PlayerInfo p, double d)
	{
		let c = CVar.GetCVar(n, p);
		return c ? c.GetFloat() : d;
	}
	clearscope static bool Flag(String n, PlayerInfo p, bool d)
	{
		let c = CVar.GetCVar(n, p);
		return c ? c.GetBool() : d;
	}
	clearscope static int Opt(String n, PlayerInfo p, int d)
	{
		let c = CVar.GetCVar(n, p);
		return c ? c.GetInt() : d;
	}

	clearscope static bool MountOn(int m, PlayerInfo p)
	{
		// The two wrists ship on, the two gun plates ship off: an on-gun
		// readout wants placing per weapon set, and one that arrives already
		// floating beside a gun reads as a bug rather than a feature.
		return Flag(RS_HandHUDMount.PrefixOf(m) .. "_on", p, m < 2);
	}
	clearscope static int MountRole(int m, PlayerInfo p)
	{
		int def = (m == RS_HandHUDMount.M_WRIST_OFF)
			? RS_HandHUDRole.VITALS : RS_HandHUDRole.AMMO;
		return Opt(RS_HandHUDMount.PrefixOf(m) .. "_role", p, def);
	}

	// UI CANNOT BE READ FROM PLAY -- the scope rule runs one way, ui reads
	// play and never the reverse -- so the painter reports on itself from
	// UiTick rather than handing a counter to the play-side line.
	private ui int mCanvasOk;       // 1 once a canvas has actually opened
	private ui int mBench;          // real paints completed on the bench path

	// ======================================================================
	// PLAY
	// ======================================================================
	override void WorldTick()
	{
		let p = players[consoleplayer];
		if (!p) return;
		let pmo = p.mo;

		// OverrideAttackPosDir is "VR is driving the hands", and requiring it
		// meant the plates could not be brought up on a desktop boot -- so
		// every fault past this line could only be looked at through a
		// headset. That is how a one-line bug cost a day. rs_handhud_bench
		// lifts the requirement so a scripted run can exercise the whole path;
		// the plates ride hand layers, so without VR they sit wherever the
		// hands would be, which is fine for a bench and useless for play.
		bool vr = pmo && pmo.OverrideAttackPosDir;
		bool on = pmo && pmo.health > 0
			&& (vr || Flag("rs_handhud_bench", p, false))
			&& Flag("rs_handhud", p, true);
		if (!on)
		{
			for (int m = 0; m < RS_HandHUDMount.COUNT; m++) Hide(p, m);
			return;
		}

		Resolve(p, pmo);

		// TWO RENDERERS, ONE SET OF NUMBERS. Resolve() has already worked out
		// what the readout says; all that differs below is how it gets in
		// front of you. 0 paints a canvas onto a model, 1 assembles digits out
		// of psprite layers the way Ermac's does. Selecting one puts the
		// other's layers away rather than leaving them behind it.
		int renderer = Opt("rs_handhud_renderer", p, 1);

		for (int m = 0; m < RS_HandHUDMount.COUNT; m++)
		{
			if (renderer == 0 && MountOn(m, p) && Visible(p, pmo, m)) Show(p, pmo, m);
			else                                                     Hide(p, m);
		}

		for (int hand = 0; hand < 2; hand++)
		{
			int m = (hand == 0) ? RS_HandHUDMount.M_WRIST_MAIN
			                    : RS_HandHUDMount.M_WRIST_OFF;
			if (renderer == 1 && MountOn(m, p) && Visible(p, pmo, m))
				ShowGlyphs(p, pmo, hand, MountRole(m, p));
			else
				HideGlyphs(p, hand);
		}

		if (Flag("rs_handhud_debug", p, false) && (level.time % 35) == 0)
			// paints=0 WITH A PLATE UP MEANS THE PAINTER IS NOT RUNNING, and
			// that is a different fault from anything it could draw wrong --
			// worth one number rather than another afternoon of guessing.
			// glyphs: how many of the twelve digit layers are installed, and
			// what the leftmost of each row resolved to. A layered renderer
			// that draws nothing looks exactly like one that is switched off,
			// so it has to say which it is.
			Console.Printf("[HandHUD/play] rend %d  roll %.0f/%.0f  up %d%d%d%d  glyphs %d/12 [%s]  wep %d/%d +%d dry=%d none=%d  hp %d ar %d keys %d",
				Opt("rs_handhud_renderer", p, 1),
				pmo.MainHandRoll, pmo.OffhandRoll,
				mUp[0], mUp[1], mUp[2], mUp[3],
				GlyphCount(p), GlyphRead(p),
				mWepLoaded, mWepCap, mWepPool, mWepDry, mWepNone,
				mHealth, mArmor, mKeyIcons.Size());
	}

	// A WRIST PLATE IS GATED, A GUN PLATE IS NOT.
	//
	// The wrist gate is what makes this hudless rather than a HUD stuck to
	// your arm: the plate is there only while that wrist is turned toward
	// your face, the way you check a watch. A gun plate needs no gate -- it
	// is on the gun, and you see it when you look at the gun.
	private bool Visible(PlayerInfo p, PlayerPawn pmo, int m)
	{
		if (RS_HandHUDMount.IsGun(m))
		{
			// Nothing to bolt a readout to if that hand is empty or holding
			// a fist stand-in.
			Weapon w = (RS_HandHUDMount.HandOf(m) == 0) ? p.ReadyWeapon : p.OffhandWeapon;
			return w != null && !RS_HandFist.IsFistClass(w.GetClass());
		}

		if (Flag("rs_handhud_always", p, false)) return true;

		int hand = RS_HandHUDMount.HandOf(m);
		double roll   = (hand == 0) ? pmo.MainHandRoll : pmo.OffhandRoll;
		// _roll_gate, NOT _roll: the renderer already owns <prefix>_roll as
		// this model's roll ROTATION through PlacementCVars, and the two
		// would fight over one name.
		double target = Num(RS_HandHUDMount.PrefixOf(m) .. "_roll_gate", p, (hand == 0) ? 90.0 : -90.0);
		double tol    = Num("rs_handhud_roll_tol", p, 45.0);

		double d = roll - target;
		while (d >  180.0) d -= 360.0;
		while (d < -180.0) d += 360.0;
		return abs(d) <= tol;
	}

	// An inert Inventory item is the layer's caller; MODELDEF puts the plate
	// model on it and names the canvas as its skin. Position, rotation and
	// scale are the engine's, through MODELDEF's PlacementCVars -- nothing
	// here touches them.
	private void Show(PlayerInfo p, PlayerPawn pmo, int m)
	{
		Name cls = RS_HandHUDMount.ClassOf(m);
		let it = pmo.FindInventory(cls);
		if (!it)
		{
			pmo.GiveInventory(cls, 1);
			it = pmo.FindInventory(cls);
			if (!it) return;
		}

		int layer = RS_HandHUDMount.LayerOf(m);
		let psp = p.FindPSprite(layer);
		if (!psp || psp.Caller != it)
		{
			State st = it.FindState("Spawn");
			if (!st) return;
			p.SetPsprite(layer, st, false, it);
			psp = p.FindPSprite(layer);
			if (!psp) return;
		}
		mUp[m] = true;
	}

	// ======================================================================
	// THE LAYERED RENDERER
	// ======================================================================

	// Three big digits over three small ones. Which numbers they are is the
	// role's business, exactly as it is for the canvas -- ammo puts loaded
	// over reserve, vitals puts health over armour.
	private void ShowGlyphs(PlayerInfo p, PlayerPawn pmo, int hand, int role)
	{
		let it = RS_HandHUDGlyphs(pmo.FindInventory('RS_HandHUDGlyphs'));
		if (!it)
		{
			pmo.GiveInventory('RS_HandHUDGlyphs', 1);
			it = RS_HandHUDGlyphs(pmo.FindInventory('RS_HandHUDGlyphs'));
			if (!it) return;
		}

		int top, bottom;
		if (role == RS_HandHUDRole.VITALS)
		{
			top    = mHealth;
			bottom = mArmor;
		}
		else
		{
			// No magazine split -- vanilla ammo and most weapon packs -- means
			// the pool IS the number, and there is nothing to put underneath.
			top    = (mWepLoaded >= 0) ? mWepLoaded : mWepPool;
			bottom = (mWepLoaded >= 0) ? mWepPool   : -1;
		}

		double x   = Num("rs_handhud_lay_x",     p,   0.0);
		double y   = Num("rs_handhud_lay_y",     p,   0.0);
		double gap = Num("rs_handhud_lay_gap",   p,  15.0);
		double sc  = Num("rs_handhud_lay_scale", p,   1.0);
		double row = Num("rs_handhud_lay_row",   p,  18.0);

		State big   = it.FindState("Big");
		State small = it.FindState("Small");
		State blank = it.FindState("Blank");

		Row(p, it, hand, 0, top,    big,   blank, x, y,       gap,       sc);
		Row(p, it, hand, 3, bottom, small, blank, x, y + row, gap * 0.3, sc);
	}

	// One row of three digits, most significant first. A leading zero is a
	// blank rather than a nought -- 007 rounds is a display, 7 is a readout --
	// and a negative value blanks the row entirely, which is how "this weapon
	// has no second number" is said.
	private void Row(PlayerInfo p, Inventory it, int hand, int slot0, int value,
	                 State digits, State blank, double x, double y,
	                 double gap, double sc)
	{
		bool shown = false;
		int v = clamp(value, -1, 999);
		for (int i = 0; i < 3; i++)
		{
			int place = (i == 0) ? 100 : ((i == 1) ? 10 : 1);
			int d = (v < 0) ? -1 : (v / place) % 10;

			// The last column always shows, so a value of 0 reads as "0".
			bool lead = (d == 0) && !shown && (i < 2);
			if (d >= 0 && !lead) shown = true;

			State st = (d < 0 || lead) ? blank : digits + d;
			Glyph(p, it, RS_HandHUDLayers.LayerOf(hand, slot0 + i), st,
			      x + gap * i, y, sc);
		}
	}

	// Put one glyph on one layer. Position is set on the psprite directly --
	// there is no model here, so PlacementCVars has nothing to act on and
	// A_OverlayOffset would need an action context we are not in.
	private void Glyph(PlayerInfo p, Inventory it, int layer, State st,
	                   double x, double y, double sc)
	{
		let psp = p.FindPSprite(layer);
		if (!psp || psp.Caller != it)
		{
			p.SetPsprite(layer, st, false, it);
			psp = p.FindPSprite(layer);
			if (!psp) return;
		}
		else if (psp.CurState != st)
		{
			psp.SetState(st);
		}
		// Not bobbing and not riding the weapon's own offset: these sit where
		// they are put, on the hand, and a gun swaying under them would make
		// the number unreadable at exactly the moment it matters.
		psp.bAddWeapon = false;
		psp.bAddBob    = false;
		psp.x     = x;
		psp.y     = y;
		psp.scale = (sc, sc);
	}

	// How many digit layers exist right now.
	private int GlyphCount(PlayerInfo p)
	{
		int n = 0;
		for (int hand = 0; hand < 2; hand++)
			for (int i = 0; i < RS_HandHUDLayers.SLOTS; i++)
				if (p.FindPSprite(RS_HandHUDLayers.LayerOf(hand, i))) n++;
		return n;
	}

	// What those layers are actually showing, as characters -- '.' for a layer
	// that is not there, '_' for a deliberate blank, otherwise the sprite
	// frame letter offset back to a digit. Reads straight off the psprites, so
	// it reports what the renderer DID rather than what it was asked for.
	private String GlyphRead(PlayerInfo p)
	{
		String rd = "";
		for (int hand = 0; hand < 2; hand++)
		{
			if (hand == 1) rd = rd .. "|";
			for (int i = 0; i < RS_HandHUDLayers.SLOTS; i++)
			{
				let psp = p.FindPSprite(RS_HandHUDLayers.LayerOf(hand, i));
				if (!psp || !psp.CurState)          { rd = rd .. "."; continue; }
				int frame = psp.CurState.frame;      // 0 == 'A' == the digit 0
				if (psp.CurState.sprite == 0)       { rd = rd .. "_"; continue; }
				rd = rd .. String.Format("%d", frame % 10);
			}
		}
		return rd;
	}

	private void HideGlyphs(PlayerInfo p, int hand)
	{
		for (int i = 0; i < RS_HandHUDLayers.SLOTS; i++)
		{
			let psp = p.FindPSprite(RS_HandHUDLayers.LayerOf(hand, i));
			if (psp) psp.SetState(null);
		}
	}

	private void Hide(PlayerInfo p, int m)
	{
		if (!mUp[m]) return;
		let psp = p.FindPSprite(RS_HandHUDMount.LayerOf(m));
		if (psp) psp.SetState(null);
		mUp[m] = false;
	}

	// ---- what the plates say ---------------------------------------------
	private void Resolve(PlayerInfo p, PlayerPawn pmo)
	{
		Weapon w = Flag("rs_handhud_swap", p, false) ? p.OffhandWeapon : p.ReadyWeapon;
		ResolveWeapon(p, pmo, w);
		ResolveVitals(pmo);
	}

	private void ResolveWeapon(PlayerInfo p, PlayerPawn pmo, Weapon w)
	{
		mWepNone   = (w == null) || RS_HandFist.IsFistClass(w.GetClass());
		mWepLoaded = -1;
		mWepCap    = 0;
		mWepPool   = 0;
		mWepDry    = false;

		if (!mWepNone)
		{
			Ammo a1 = w.Ammo1;
			mWepPool = a1 ? a1.Amount : -1;

			int loaded, cap;
			[loaded, cap] = RS_HandHUDRead.Magazine(w, p, pmo);
			if (loaded >= 0)
			{
				mWepLoaded = loaded;
				mWepCap    = (cap > 0) ? cap : loaded;
			}
			mWepDry = (mWepLoaded >= 0) ? (mWepLoaded <= 0) : (mWepPool == 0);
		}

		mSigAmmo = (mWepNone ? 1 : 0) + (mWepDry ? 2 : 0)
		         + (mWepLoaded + 1) * 4 + mWepCap * 4096 + mWepPool * 1048576;
	}

	private void ResolveVitals(PlayerPawn pmo)
	{
		mHealth = pmo.health;
		let armor = BasicArmor(pmo.FindInventory('BasicArmor'));
		mArmor = (armor && armor.Amount > 0) ? armor.Amount : 0;
		if (mArmor > 0) mArmorIcon = armor.Icon; else mArmorIcon.SetInvalid();

		mKeyIcons.Clear();
		for (Inventory it = pmo.Inv; it != null; it = it.Inv)
		{
			let k = Key(it);
			if (k && k.Icon.IsValid()) mKeyIcons.Push(k.Icon);
		}

		mSigVit = mHealth + mArmor * 1024 + mKeyIcons.Size() * 1048576
		        + (mArmorIcon.IsValid() ? mArmorIcon.GetIndex() * 8 : 0);
	}

	// `netevent rs-handhud-probe` -- what a mod actually holds, for finding
	// the field name to put in rs_handhud_magfield. Typed into the console;
	// it needs no bind and no KEYCONF entry.
	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.Player != consoleplayer) return;
		if (!(e.Name ~== "rs-handhud-probe")) return;

		let p = players[consoleplayer];
		if (!p || !p.mo) return;
		RS_HandHUDRead.Probe(p.ReadyWeapon,   p.mo, "main hand");
		RS_HandHUDRead.Probe(p.OffhandWeapon, p.mo, "off hand");
	}

	// ======================================================================
	// UI -- the painting
	// ======================================================================
	private ui Font bigFont()
	{
		Font f = Font.GetFont("HUDFONT_DOOM");
		if (!f) f = Font.GetFont("BIGFONT");
		if (!f) f = Font.GetFont("SMALLFONT");
		return f;
	}
	private ui Font smallFont()
	{
		Font f = Font.GetFont("INDEXFONT_DOOM");
		if (!f) f = Font.GetFont("SMALLFONT");
		if (!f) f = Font.GetFont("BIGFONT");
		return f;
	}

	override void UiTick()
	{
		let p = players[consoleplayer];
		if (!p || !p.mo) return;

		// BENCH CHECK, ahead of every gate.
		//
		// A wrist plate needs VR before it will even come up, so the parts
		// that were failing could only ever be looked at through a headset --
		// which is how a one-line fault turned into a day. None of the DRAWING
		// half needs VR: the canvases are declared by ANIMDEFS, the fonts come
		// from the iwad, and Canvas.DrawText either works or aborts. So this
		// exercises all of it on a bare boot and says so on stdout, where a
		// scripted run can read it.
		if (Flag("rs_handhud_debug", p, false) && (level.time % 35) == 3)
			BenchCheck(p);

		if (!Flag("rs_handhud", p, true)) return;

		// The mugshot animates on its own, so it is the one thing that can
		// change with no number moving.
		TextureID mug;
		mug.SetInvalid();
		if (Flag("rs_handhud_mugshot", p, true) && StatusBar)
			mug = StatusBar.GetMugShot(5);
		int mugSig = mug.IsValid() ? mug.GetIndex() : 0;

		bool test = Flag("rs_handhud_selftest", p, false);

		for (int m = 0; m < RS_HandHUDMount.COUNT; m++)
		{
			if (!mUp[m]) continue;

			// PAINT EVERY TIC. There was a dirty check here -- a signature
			// of every number, skip the paint when it has not moved -- and it
			// is what left the plates grey.
			//
			// Two ways it lost, and both are the same mistake. A canvas is
			// ENGINE state, not ours: it does not survive its plate being
			// hidden, and a wrist plate is hidden and re-shown constantly
			// because that is what the roll gate does. So the plate came back
			// up with a blank canvas, the numbers had not changed, and the
			// dirty check said there was nothing to do -- forever. The other
			// way is emptier still: at the first tic the stored signature is
			// zero, and any weapon state that also hashes to zero is never
			// painted a first time at all.
			//
			// It was saving four 128x64 canvases a tic, which is nothing, to
			// buy an entire class of "why is it blank". Not a trade worth
			// making twice.
			Paint(m, MountRole(m, p), mug, test, p);
			mPaints++;
		}

		// PAINTS 0 WITH A PLATE UP MEANS THE PAINTER NEVER RAN, and canvas 0
		// means it ran but the canvas texture would not open. Those are three
		// different faults -- not running, not opening, drawing the wrong
		// thing -- and telling them apart is what an afternoon went on.
		if (Flag("rs_handhud_debug", p, false) && (level.time % 35) == 0)
			Console.Printf("[HandHUD/ui] paints %d  canvasopen %d  fonts %d/%d",
				mPaints, mCanvasOk,
				bigFont() ? 1 : 0, smallFont() ? 1 : 0);
	}

	// Open every canvas, draw the known pattern into it, and report -- with no
	// player gate, no VR and no plate up. Answers the only three questions
	// that are not about VR: does the canvas texture exist, does drawing into
	// it survive, and did the fonts resolve.
	private ui void BenchCheck(PlayerInfo p)
	{
		String canv = "";
		for (int m = 0; m < RS_HandHUDMount.COUNT; m++)
		{
			let cv = new("RS_HandHUDCanvas");
			bool opened = cv.Begin(RS_HandHUDMount.CanvasOf(m));
			canv = canv .. (opened ? "1" : "0");
			if (opened)
			{
				// The known pattern first -- bars and text, so a bad draw tag
				// aborts the VM HERE, on a bench run, and not in a headset.
				cv.SelfTest(bigFont());
				mCanvasOk = 1;
			}
		}

		// THEN THE REAL THING. SelfTest only proves the canvas takes marks;
		// PaintVitals and PaintAmmo are the code that actually runs in the
		// headset, and they draw a mugshot texture, an armour icon, key icons
		// and several strings that SelfTest never touches. Running them here
		// means the whole drawing half is exercised on a bare boot -- the
		// reason a day went by is that none of it could be reached without
		// putting the headset back on.
		//
		// mBench counts completed real paints. If a paint aborts the VM the
		// count stops climbing and the line stops printing, which is itself
		// the answer.
		TextureID mug;
		mug.SetInvalid();
		if (Flag("rs_handhud_mugshot", p, true) && StatusBar)
			mug = StatusBar.GetMugShot(5);

		for (int m = 0; m < RS_HandHUDMount.COUNT; m++)
		{
			Paint(m, MountRole(m, p), mug, false, p);
			mBench++;
		}

		Console.Printf("[HandHUD/bench] canvas %s  realpaints %d  mug %d  fonts %d/%d  live paints %d",
			canv, mBench, mug.IsValid() ? 1 : 0,
			bigFont() ? 1 : 0, smallFont() ? 1 : 0, mPaints);
	}

	private ui void Paint(int m, int role, TextureID mug, bool test, PlayerInfo p)
	{
		let cv = new("RS_HandHUDCanvas");
		if (cv.Begin(RS_HandHUDMount.CanvasOf(m)))
		{
			mCanvasOk = 1;
		}
		else
		{
			if (Flag("rs_handhud_debug", p, false))
				Console.Printf("\cg[HandHUD] %s: canvas %s is not declared",
					RS_HandHUDMount.NameOf(m), RS_HandHUDMount.CanvasOf(m));
			return;
		}

		Font big = bigFont();
		Font sml = smallFont();

		if (test) { cv.SelfTest(big); return; }
		if (!big)
		{
			if (Flag("rs_handhud_debug", p, false))
				Console.Printf("\cg[HandHUD] no usable font -- HUDFONT_DOOM, BIGFONT and SMALLFONT all missing");
			return;
		}

		if (role == RS_HandHUDRole.VITALS)
		{
			PaintVitals(cv, big, mug);
		}
		else if (role == RS_HandHUDRole.BOTH)
		{
			PaintVitals(cv, big, mug);
			PaintAmmo(cv, big, sml, 2);
		}
		else
		{
			PaintAmmo(cv, big, sml, RS_HandHUDCanvas.PANEL_ALL);
		}
	}

	// loaded / capacity across the plate, reserve under it. With no magazine
	// split -- vanilla ammo, and most weapon packs -- the pool alone, big.
	private ui void PaintAmmo(RS_HandHUDCanvas cv, Font big, Font sml, int panel)
	{
		if (mWepNone)
		{
			cv.TextCentred(sml, Font.CR_DARKGRAY, panel, 24, "--");
			return;
		}

		int col = mWepDry ? Font.CR_DARKRED : Font.CR_UNTRANSLATED;
		if (mWepLoaded >= 0)
		{
			cv.TextCentred(big, col, panel, 8, String.Format("%d / %d", mWepLoaded, mWepCap));
			if (mWepPool >= 0)
				cv.TextCentred(sml, Font.CR_UNTRANSLATED, panel, 36, String.Format("%d", mWepPool));
		}
		else if (mWepPool >= 0)
		{
			cv.TextCentred(big, col, panel, 20, String.Format("%d", mWepPool));
		}
		else
		{
			cv.TextCentred(sml, Font.CR_DARKGRAY, panel, 24, "--");
		}
	}

	// Mugshot on the left, health and armour beside it, keys along the bottom.
	private ui void PaintVitals(RS_HandHUDCanvas cv, Font big, TextureID mug)
	{
		int all = RS_HandHUDCanvas.PANEL_ALL;

		int x0 = 6;
		if (mug.IsValid())
		{
			cv.Icon(mug, all, 4, 6, 28, 34);
			x0 = 38;
		}

		TextureID med = TexMan.CheckForTexture("MEDIA0", TexMan.Type_Any, TexMan.TryAny);
		cv.Icon(med, all, x0, 4, 12, 12);
		cv.Text(big, Font.CR_UNTRANSLATED, all, x0 + 16, 4, String.Format("%d", mHealth));

		if (mArmor > 0)
		{
			cv.Icon(mArmorIcon, all, x0, 22, 12, 12);
			cv.Text(big, Font.CR_UNTRANSLATED, all, x0 + 16, 22, String.Format("%d", mArmor));
		}

		int kx = x0;
		for (int i = 0; i < mKeyIcons.Size() && i < 6; i++)
		{
			cv.Icon(mKeyIcons[i], all, kx, 44, 10, 14);
			kx += 12;
		}
	}
}

// =====================================================================
// RS_HandHUDRead -- READING SOMEBODY ELSE'S MAGAZINE.
//
// THREE SHAPES, AND A MOD PICKS ONE:
//
//   a FIELD on the weapon    modern ZScript. Read by name through the fork's
//                            reflection natives -- this package never has to
//                            know the class exists.
//   Ammo2                    the classic ZDoom idiom.
//   an INVENTORY ITEM        DECORATE-era mods. Project Brutality counts the
//                            pump shotgun's shells in an item called
//                            PumpshotgunMagazine on the PLAYER; there is no
//                            field anywhere to read.
//
// The third is the one that needs work, because nothing links the item to the
// gun except the two names agreeing. See ItemMagazine.
// =====================================================================
class RS_HandHUDRead
{
	// A LOOKUP FUNCTION, NOT AN ARRAY. ZScript's `static const X[]` takes
	// numeric types only, and a class may not hold a static member variable
	// at all. Ordered by how unambiguous the name is: "mag" and "clip" are
	// last because plenty of things are called that without being a count.
	const MAG_COUNT = 24;
	private static String MagName(int i)
	{
		switch (i)
		{
		case  0: return "MagazineAmount";  case  1: return "magazineAmount";
		case  2: return "MagAmount";       case  3: return "magAmount";
		case  4: return "AmmoInClip";      case  5: return "ammoInClip";
		case  6: return "RoundsLoaded";    case  7: return "roundsLoaded";
		case  8: return "CurrentMag";      case  9: return "currentMag";
		case 10: return "MagCount";        case 11: return "magCount";
		case 12: return "ClipAmount";      case 13: return "clipAmount";
		case 14: return "ClipCount";       case 15: return "clipCounter";
		case 16: return "Loaded";          case 17: return "loaded";
		case 18: return "Magazine";        case 19: return "magazine";
		case 20: return "Clip";            case 21: return "clip";
		case 22: return "Mag";             case 23: return "mag";
		}
		return "";
	}

	const CAP_COUNT = 18;
	private static String CapName(int i)
	{
		switch (i)
		{
		case  0: return "MagazineCapacity"; case  1: return "magazineCapacity";
		case  2: return "MagCapacity";      case  3: return "magCapacity";
		case  4: return "MagazineSize";     case  5: return "magazineSize";
		case  6: return "MagSize";          case  7: return "magSize";
		case  8: return "ClipCapacity";     case  9: return "clipCapacity";
		case 10: return "ClipSize";         case 11: return "clipSize";
		case 12: return "MaxMagazine";      case 13: return "maxMagazine";
		case 14: return "MaxMag";           case 15: return "maxMag";
		case 16: return "Capacity";         case 17: return "capacity";
		}
		return "";
	}

	// loaded, capacity. loaded < 0 means "nothing here knows".
	static int, int Magazine(Weapon w, PlayerInfo p, PlayerPawn pmo)
	{
		if (!w || !level) return -1, 0;

		// The manual override wins outright.
		let cv = CVar.GetCVar("rs_handhud_magfield", p);
		String forced = cv ? cv.GetString() : "";
		if (forced.Length() > 0)
		{
			int v;
			if (level.GetFieldInt(w, forced, v)) return v, CapFor(w);
			return -1, 0;
		}

		for (int i = 0; i < MAG_COUNT; i++)
		{
			int v;
			if (level.GetFieldInt(w, MagName(i), v) && v >= 0)
				return v, CapFor(w);
		}

		// Ammo2 as a magazine: a different pool from Ammo1, with a real cap.
		if (w.Ammo2 && w.Ammo1 != w.Ammo2 && w.Ammo2.MaxAmount > 1)
			return w.Ammo2.Amount, w.Ammo2.MaxAmount;

		if (pmo)
		{
			int il, ic;
			[il, ic] = ItemMagazine(w, pmo);
			if (il >= 0) return il, ic;
		}
		return -1, 0;
	}

	private static int CapFor(Weapon w)
	{
		for (int i = 0; i < CAP_COUNT; i++)
		{
			int v;
			if (level.GetFieldInt(w, CapName(i), v) && v > 0)
				return v;
		}
		return 0;
	}

	// A MAGAZINE KEPT AS AN INVENTORY ITEM.
	//
	// THREE TESTS, and all three are needed:
	//
	//   1. the item's name ends in a magazine word.
	//   2. what is left when that word is removed appears in the weapon's own
	//      class name. PumpshotgunMagazine -> "pumpshotgun", which sits inside
	//      "pbpumpshotgun".
	//   3. IT CAN HOLD MORE THAN ONE. This is what separates a magazine from
	//      the flags these mods are full of -- PBPumpShotgunHasUnloaded,
	//      RevolverHasUnloaded and FlamerUnloaded all end in "loaded" and are
	//      all MaxAmount 1.
	//
	// MaxAmount doubles as the capacity: it is the number the mod already had
	// to declare for the item to work at all.
	static int, int ItemMagazine(Weapon w, PlayerPawn pmo)
	{
		if (!w || !pmo) return -1, 0;
		String wn = Squash(w.GetClassName());
		if (wn.Length() < 3) return -1, 0;

		Inventory best = null;
		int bestStem = 0;

		for (Inventory it = pmo.Inv; it != null; it = it.Inv)
		{
			if (it.MaxAmount <= 1) continue;          // a flag, not a magazine
			if (Ammo(it)) continue;                   // the pool, not a magazine

			String stem = MagStem(Squash(it.GetClassName()));
			if (stem.Length() < 3) continue;
			if (wn.IndexOf(stem) < 0) continue;

			// Longest stem wins: "pumpshotgun" beats "shotgun" on a weapon
			// whose name holds both.
			if (int(stem.Length()) > bestStem)
			{
				bestStem = stem.Length();
				best = it;
			}
		}

		if (!best) return -1, 0;
		return best.Amount, best.MaxAmount;
	}

	// Lowercased with the separators taken out, so PB_SGMagazine and
	// PBSGMagazine compare the same way.
	private static String Squash(String s)
	{
		s = s.MakeLower();
		s.Replace("_", "");
		s.Replace("-", "");
		s.Replace(" ", "");
		return s;
	}

	// The name with its magazine word removed, or "" if it had none. Longest
	// words first, or every magazine keeps an "azine".
	private static String MagStem(String n)
	{
		for (int i = 0; i < 6; i++)
		{
			String word = MagWord(i);
			int at = n.IndexOf(word);
			if (at < 0) continue;
			if (at + word.Length() != n.Length()) continue;   // must END with it
			return n.Left(at);
		}
		return "";
	}

	private static String MagWord(int i)
	{
		switch (i)
		{
		case 0: return "magazine";
		case 1: return "rounds";
		case 2: return "shells";
		case 3: return "loaded";
		case 4: return "clip";
		case 5: return "mag";
		}
		return "";
	}

	// EVERY FIELD ON THE WEAPON, plus the inventory candidates, printed. The
	// answer to "what does this mod call its magazine" for a mod nobody has
	// read the source of.
	static void Probe(Weapon w, PlayerPawn pmo, String label)
	{
		if (!w) { Console.Printf("\cg[HandHUD probe] %s: no weapon", label); return; }
		Console.Printf("\cf[HandHUD probe] %s = %s", label, w.GetClassName());

		if (w.Ammo1)
			Console.Printf("   Ammo1  %-22s %d / %d", w.Ammo1.GetClassName(), w.Ammo1.Amount, w.Ammo1.MaxAmount);
		if (w.Ammo2)
			Console.Printf("   Ammo2  %-22s %d / %d", w.Ammo2.GetClassName(), w.Ammo2.Amount, w.Ammo2.MaxAmount);

		if (pmo)
		{
			int il, ic;
			[il, ic] = ItemMagazine(w, pmo);
			if (il >= 0) Console.Printf("\cd   matched inventory magazine: %d / %d", il, ic);

			Console.Printf("   inventory items that could be a magazine:");
			for (Inventory it = pmo.Inv; it != null; it = it.Inv)
			{
				if (it.MaxAmount <= 1 || Ammo(it)) continue;
				Console.Printf("      %-26s %d / %d", it.GetClassName(), it.Amount, it.MaxAmount);
			}
		}

		int n = level.FieldCount(w);
		Console.Printf("   %d fields:", n);
		for (int i = 0; i < n; i++)
		{
			String fname, ftype;
			if (!level.FieldAt(w, i, fname, ftype)) continue;
			int v;
			if (level.GetFieldInt(w, fname, v))
				Console.Printf("      %-26s %-10s = %d", fname, ftype, v);
			else
				Console.Printf("      %-26s %-10s", fname, ftype);
		}
	}
}
