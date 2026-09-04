// RS_HandHUD -- THE HUD ON YOUR HANDS.
//
// Two plates, one strapped to each hand, drawn the way the hands themselves
// are drawn: a model on a psprite layer that rides the controller at render
// rate (rs_hands.zs LAYER_MAIN/OFF, RR_Ammo's in-hand magazine). No world
// billboard, no per-tic placement, no per-weapon calibration -- the hand is
// the one thing whose pose is exact, and a fixed offset in its frame lands on
// the same spot of the wrist every frame.
//
// Each plate is skinned with a CANVAS TEXTURE (ANIMDEFS RSHUDMAIN / RSHUDOFF)
// painted from ZScript, the mechanism the wheel already uses for its card
// faces. The content is the stock HUD: the big red status-bar digits, the
// small yellow ones, MEDIA0, the armor pickup icon, the key icons and the
// mugshot. Nothing on either plate needs an asset this package does not
// already get for free from the IWAD.
//
// ROLES. The WEAPON plate follows whatever is in that hand -- loaded /
// capacity in big digits, reserve under it. The VITALS plate carries the
// mugshot, health, armor and keys. Weapon on the main wrist, vitals on the
// off forearm by default; rs_handhud_swap flips them for a left-hander.
//
// THE WRIST GATE is what makes this hudless rather than a HUD stuck to your
// hand: a plate is faded out unless that wrist is rolled toward your face,
// the way you check a watch. rs_handhud_always switches the gate off while
// the plates are being placed.
//
// TWO SCOPES, ON PURPOSE. WorldTick (play) owns the layers, the gate and the
// numbers; it cannot touch the status bar. UiTick (ui) owns the painting; it
// can read the numbers play left behind and ask StatusBar for the mugshot.
// The play side changes the world, the ui side only draws -- which is also
// why the ui side never writes anything the play side reads.

class RS_HandHUDPlateMain : Inventory
{
	Default
	{
		Inventory.MaxAmount 1;
		Inventory.InterHubAmount 1;
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
		+INVENTORY.QUIET
		// REQUIRED, and it is what was missing on the first build: with a TNT1
		// Spawn state there is no FrameIndex for the model lookup to hit, so
		// the psprite has to resolve its model through BaseSpriteModelFrames
		// (MODELDEF BaseFrame) -- and that path is only consulted for a
		// +DECOUPLEDANIMATIONS actor. Without the flag the layer fell through
		// to the sprite path and drew nothing. Same flag on RS_HandIdle and
		// RR_AmmoInHand, for the same reason.
		+DECOUPLEDANIMATIONS
	}
	States
	{
	Spawn:
		TNT1 A -1;
		Stop;
	}
}
class RS_HandHUDPlateOff : RS_HandHUDPlateMain {}

class RS_HandHUD : EventHandler
{
	// Beside the hand (900000) and the reload's magazine (900010).
	const LAYER_MAIN = 900020;
	const LAYER_OFF  = 1900020;

	// Must match the canvastexture lines in ANIMDEFS.
	const CANVAS_W = 128;
	const CANVAS_H = 64;

	// ---- play state, read by ui -------------------------------------------
	private double mAlpha[2];       // current fade per hand
	private bool   mLayerUp[2];     // the psprite is currently installed

	// The numbers, resolved in play scope because the resolvers are play.
	private int  mWepLoaded;        // -1: no magazine split, show the pool only
	private int  mWepCap;
	private int  mWepPool;          // reserve (or the whole pool)
	private bool mWepDry;
	private bool mWepNone;          // no weapon in the weapon hand
	private int  mHealth;
	private int  mArmor;
	private TextureID mArmorIcon;
	private Array<TextureID> mKeyIcons;
	private int  mSigWep;           // change signatures, so ui repaints only on change
	private int  mSigVit;

	// ---- ui state --------------------------------------------------------
	private ui int mPaintedWep;
	private ui int mPaintedVit;
	private ui int mPaintedMug;

	private clearscope static double cvNum(string name, PlayerInfo p, double fb)
	{
		let c = CVar.GetCVar(name, p);
		return c ? c.GetFloat() : fb;
	}
	private clearscope static bool cvOn(string name, PlayerInfo p, bool fb)
	{
		let c = CVar.GetCVar(name, p);
		return c ? c.GetBool() : fb;
	}

	// Which hand carries the weapon plate. The other carries vitals.
	private clearscope static int weaponHand(PlayerInfo p) { return cvOn("rs_handhud_swap", p, false) ? 1 : 0; }
	clearscope static int LayerFor(int hand) { return (hand == 0) ? LAYER_MAIN : LAYER_OFF; }
	clearscope static Name ClassFor(int hand) { return (hand == 0) ? 'RS_HandHUDPlateMain' : 'RS_HandHUDPlateOff'; }
	clearscope static String CanvasFor(int hand) { return (hand == 0) ? "RSHUDMAIN" : "RSHUDOFF"; }

	// ======================================================================
	// PLAY
	// ======================================================================
	override void WorldTick()
	{
		let p = players[consoleplayer];
		if (!p) return;
		let pmo = p.mo;

		bool on = pmo && pmo.health > 0 && pmo.OverrideAttackPosDir && cvOn("rs_handhud", p, true);
		if (!on)
		{
			Hide(p, 0);
			Hide(p, 1);
			return;
		}

		Resolve(p, pmo);

		double fade = max(1.0, cvNum("rs_handhud_fade", p, 6.0));
		double scale = cvNum("rs_handhud_scale", p, 1.0);
		if (scale <= 0.0) scale = 1.0;

		bool dbg = cvOn("rs_handhud_debug", p, false);
		if (dbg && (level.time % 35) == 0)
		{
			// Once a second: the two rolls the gate reads, so the targets can
			// be set from real numbers instead of guessed signs.
			Console.Printf("[HandHUD] roll main %.0f off %.0f | gate main %d off %d | layers %d %d | wep %s %d/%d +%d | hp %d ar %d keys %d",
				pmo.MainHandRoll, pmo.OffhandRoll, Gate(p, pmo, 0), Gate(p, pmo, 1), mLayerUp[0], mLayerUp[1],
				mWepNone ? "none" : "ok", mWepLoaded, mWepCap, mWepPool, mHealth, mArmor, mKeyIcons.Size());
		}

		for (int h = 0; h < 2; h++)
		{
			double target = Gate(p, pmo, h) ? 1.0 : 0.0;
			if (mAlpha[h] < target) mAlpha[h] = min(target, mAlpha[h] + 1.0 / fade);
			else if (mAlpha[h] > target) mAlpha[h] = max(target, mAlpha[h] - 1.0 / fade);

			if (mAlpha[h] <= 0.01) { Hide(p, h); continue; }
			Show(p, pmo, h, scale, mAlpha[h]);
		}
	}

	// THE WRIST GATE. Roll the wrist toward your face and the plate comes up.
	// The engine's roll fields turn opposite to actor roll (rs_held.zs), so
	// the target angles are simply whatever reads right in the headset --
	// tune rs_handhud_roll_main/off rather than reasoning about the sign.
	private bool Gate(PlayerInfo p, PlayerPawn pmo, int hand)
	{
		if (cvOn("rs_handhud_always", p, false)) return true;
		double roll   = (hand == 0) ? pmo.MainHandRoll : pmo.OffhandRoll;
		double target = cvNum(hand == 0 ? "rs_handhud_roll_main" : "rs_handhud_roll_off", p, hand == 0 ? 90.0 : -90.0);
		double tol    = cvNum("rs_handhud_roll_tol", p, 45.0);
		double d = roll - target;
		while (d >  180.0) d -= 360.0;
		while (d < -180.0) d += 360.0;
		return abs(d) <= tol;
	}

	// Same plumbing as RR_Ammo.Show: an inert Inventory item is the layer's
	// caller, MODELDEF puts the plate model on it, the canvas is its skin.
	private void Show(PlayerInfo p, PlayerPawn pmo, int hand, double scale, double alpha)
	{
		Name cls = ClassFor(hand);
		let it = pmo.FindInventory(cls);
		if (!it)
		{
			pmo.GiveInventory(cls, 1);
			it = pmo.FindInventory(cls);
			if (!it) return;
		}
		int layer = LayerFor(hand);
		let psp = p.FindPSprite(layer);
		if (!psp || psp.Caller != it)
		{
			State st = it.FindState("Spawn");
			if (!st) return;
			p.SetPsprite(layer, st, false, it);
			psp = p.FindPSprite(layer);
			if (!psp) return;
		}
		psp.scale = (scale, scale);
		psp.alpha = alpha;


		// ANCHORED TO THE HAND, which is what makes the placement sliders
		// below do anything at all: AnchorOfs and AnchorAngles are only read
		// for an ANCHORED layer (r_data/models.cpp -- `isAnchored ?
		// psp->AnchorOfs.X : 0`), and an unanchored psprite has no runtime
		// offset of any kind, only its baked MODELDEF numbers.
		//
		// Anchoring also puts the plate on the hand's palm BONE rather than
		// the controller origin, so it stays where you put it when the hand's
		// own placement sliders move.
		//
		// The hand's layer has to be DRAWN first -- psprites draw in id order
		// and a bone is only known once its model has been drawn -- which is
		// why these ids (900020 / 1900020) sit above the hands' (900000 /
		// 1900000). Literals rather than RS_Hands' consts: this is a separate
		// package and should not need that class to exist. With rs_hands off
		// there is no hand model to anchor to, the engine ignores the anchor,
		// and the plate falls back to its MODELDEF offsets.
		psp.AnchorLayer = (hand == 0) ? 900000 : 1900000;
		psp.AnchorBone  = 'HANDPALM_joint';

		String pre = (hand == 0) ? "rs_handhud_m" : "rs_handhud_o";
		psp.AnchorOfs = (cvNum(pre .. "_ofs_x", p, 0.0),
		                 cvNum(pre .. "_ofs_y", p, 0.0),
		                 cvNum(pre .. "_ofs_z", p, 0.0));
		psp.AnchorAngles = (cvNum(pre .. "_yaw",   p, 0.0),
		                    cvNum(pre .. "_pitch", p, 0.0),
		                    cvNum(pre .. "_roll",  p, 0.0));

		mLayerUp[hand] = true;
	}

	private void Hide(PlayerInfo p, int hand)
	{
		mAlpha[hand] = 0.0;
		if (!mLayerUp[hand]) return;
		let psp = p.FindPSprite(LayerFor(hand));
		if (psp) psp.SetState(null);
		mLayerUp[hand] = false;
	}

	// The numbers. Play scope, because wr_Stats / RR_Mag / RR_Feed are play.
	private void Resolve(PlayerInfo p, PlayerPawn pmo)
	{
		int wh = weaponHand(p);
		Weapon w = (wh == 0) ? p.ReadyWeapon : p.OffhandWeapon;

		mWepNone   = (w == null) || RS_HandFist.IsFistClass(w.GetClass());
		mWepLoaded = -1;
		mWepCap    = 0;
		mWepPool   = 0;
		mWepDry    = false;

		if (!mWepNone)
		{
			Ammo a1 = w.Ammo1;
			int pool = a1 ? a1.Amount : -1;

			if (a1 && cvOn("rr_magazines", p, false))
			{
				// The reload lane's split: the Ammo item IS the magazine and
				// RR_Reserve holds the pool behind it.
				int f, a;
				[f, a] = RR_Feed.Resolve(w, p);
				mWepLoaded = a1.Amount;
				mWepCap    = RR_Feed.CapOf(a, w, p);
				mWepPool   = RR_Mag.Pool(pmo, a1);
			}
			else
			{
				// A weapon that keeps its own magazine. THREE PLACES TO LOOK,
				// in order of how much they know:
				//
				//   1. a NAMED FIELD on the weapon, read by reflection. Most
				//      mods with magazines keep the count in an int on the
				//      weapon class; the engine can read one by name without
				//      this package knowing the class exists. RS_HandHUDRead
				//      below holds the list of names worth trying and caches
				//      the one that answered.
				//   2. wr_Stats, which knows the handful of mods the wheel
				//      has real compat readers for.
				//   3. Ammo2 as a magazine, then the flat pool.
				int fLoaded, fCap;
				[fLoaded, fCap] = RS_HandHUDRead.Magazine(w, p);
				if (fLoaded >= 0)
				{
					mWepLoaded = fLoaded;
					mWepCap    = (fCap > 0) ? fCap : fLoaded;
					mWepPool   = pool;
					mWepDry    = (fLoaded <= 0);
					mSigWep = 4 + (mWepLoaded + 1) * 4 + mWepCap * 4096 + mWepPool * 1048576;
					ResolveVitals(pmo);
					return;
				}

				int src, loaded, cap;
				[src, loaded, cap] = wr_Stats.Magazine(w);
				if (src != wr_Stats.SRC_UNKNOWN && src != wr_Stats.SRC_MASKED && cap > 0)
				{
					if (loaded < 0)
					{
						// wr_Rig.hasMagazine's test, inlined (it is private): Ammo2 is a
						// magazine only when it is a different pool and not an alt-fire pool.
						bool mag2 = w.Ammo2 != null && w.Ammo1 != w.Ammo2 && !wr_Rig.hasAltFire(w);
						loaded = mag2 ? w.Ammo2.Amount : (a1 ? a1.Amount : 0);
					}
					mWepLoaded = loaded;
					mWepCap    = cap;
					mWepPool   = pool;
				}
				else
				{
					mWepPool = pool;
				}
			}
			mWepDry = (mWepLoaded >= 0) ? (mWepLoaded <= 0) : (pool == 0);
		}

		// Change signature. Cheap to compute, and it is what keeps the painter
		// idle on the tics where nothing moved.
		mSigWep = (mWepNone ? 1 : 0) + (mWepDry ? 2 : 0) + (mWepLoaded + 1) * 4
		        + mWepCap * 4096 + mWepPool * 1048576;

		ResolveVitals(pmo);
	}

	// The vitals half, split out so the weapon half can return early once it
	// has an answer without leaving health and armour a tic stale.
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

		mSigVit = mHealth + mArmor * 1024 + mKeyIcons.Size() * 1048576 + (mArmorIcon.IsValid() ? mArmorIcon.GetIndex() * 8 : 0);
	}

	// `netevent rs-handhud-probe` -- dump both hands' weapons, every field on
	// them and their value. Typed straight into the console; it needs no bind
	// and no KEYCONF entry.
	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.Player != consoleplayer) return;
		if (!(e.Name ~== "rs-handhud-probe")) return;

		let p = players[consoleplayer];
		if (!p || !p.mo) return;
		RS_HandHUDRead.Probe(p.ReadyWeapon,   "main hand");
		RS_HandHUDRead.Probe(p.OffhandWeapon, "off hand");
	}

	// ======================================================================
	// UI -- the painting
	// ======================================================================
	override void UiTick()
	{
		let p = players[consoleplayer];
		if (!p || !p.mo) return;
		if (!cvOn("rs_handhud", p, true)) return;

		int wh = weaponHand(p);

		// The mugshot animates on its own (pain, grin, dead); it is the one
		// thing that can change with no number moving.
		TextureID mug;
		mug.SetInvalid();
		if (cvOn("rs_handhud_mugshot", p, true) && StatusBar)
			mug = StatusBar.GetMugShot(5);
		int mugSig = mug.IsValid() ? mug.GetIndex() : 0;

		if (mPaintedWep != mSigWep)
		{
			PaintWeapon(CanvasFor(wh));
			mPaintedWep = mSigWep;
			if (cvOn("rs_handhud_debug", p, false))
				Console.Printf("[HandHUD] painted %s: canvas=%d bigfont=%d smallfont=%d",
					CanvasFor(wh),
					TexMan.GetCanvas(CanvasFor(wh)) ? 1 : 0,
					bigFont() ? 1 : 0, smallFont() ? 1 : 0);
		}
		if (mPaintedVit != mSigVit || mPaintedMug != mugSig)
		{
			PaintVitals(CanvasFor(1 - wh), mug);
			mPaintedVit = mSigVit;
			mPaintedMug = mugSig;
		}
	}

	private ui Font bigFont()
	{
		// The status bar's own digits. BIGFONT is the fallback rather than
		// SMALLFONT because a number nobody can read is the whole failure this
		// plate exists to avoid.
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

	// A CANVAS SAMPLES BOTTOM-UP. Everything below authors in natural
	// coordinates -- y = 0 is the top of the plate as you look at it -- and
	// this converts. The wheel's card faces hit the same thing and solve it
	// the same way; drawing top-down without it puts every row on the wrong
	// half of the plate, mirrored.
	private ui static int fy(int y) { return CANVAS_H - y; }

	// NO DTA_ TAGS ON TEXT, DELIBERATELY, AND THIS IS WHY THE PLATE WAS BLANK.
	//
	// Canvas.DrawText takes the same vararg tag list as DrawTexture, but not
	// every tag is valid for text -- and an invalid one is a VM abort, not a
	// warning. The abort lands mid-paint, so the bed had already been drawn
	// and nothing after it ever was: a black plate with a rim, which is
	// exactly what this looked like in the headset. A headless load test
	// cannot catch it because the paint only runs once there is a player.
	//
	// So text is drawn plain, and SIZE COMES FROM THE FONT AND THE CANVAS
	// instead: at 128x64 the stock 14px digits are a fifth of the plate's
	// height rather than a tenth, without a scaling tag anywhere.
	private ui void row(Canvas c, Font f, int col, int x, int yTop, String text)
	{
		if (!f || text.Length() == 0) return;
		c.DrawText(f, col, x, fy(yTop + f.GetHeight()), text);
		// The line above is the whole call. Nothing else may be added to it.
	}

	// Textures keep DTA_DestWidth/DestHeight, which the wheel already proves
	// on this engine's canvases -- it is the text tags that were the problem.
	private ui void icon(Canvas c, TextureID t, int x, int yTop, int w, int h)
	{
		if (!t.IsValid()) return;
		c.DrawTexture(t, false, x, fy(yTop + h),
			DTA_DestWidth, w, DTA_DestHeight, h, DTA_FlipY, true);
	}

	private ui void bed(Canvas c, String canvasName)
	{
		// Translucent, the way the wheel declares its card faces -- without
		// this the plate composites as an opaque black slab.
		TexMan.SetCanvasTextureTranslucent(canvasName, true);
		c.Clear(0, 0, CANVAS_W, CANVAS_H, Color(255, 10, 11, 13));
		c.DrawLineFrame(Color(255, 90, 96, 104), 1, 1, CANVAS_W - 2, CANVAS_H - 2, 1);
	}

	// Weapon plate:
	//     3 / 12        loaded / capacity
	//       128         reserve
	// or, with no magazine split, the pool alone.
	private ui void PaintWeapon(String canvasName)
	{
		let c = TexMan.GetCanvas(canvasName);
		if (!c) return;
		bed(c, canvasName);

		Font big = bigFont();
		Font sml = smallFont();
		if (!big) return;

		if (mWepNone)
		{
			row(c, big, Font.CR_DARKGRAY, 8, 20, "--");
			return;
		}

		int col = mWepDry ? Font.CR_DARKRED : Font.CR_UNTRANSLATED;
		if (mWepLoaded >= 0)
		{
			String top = String.Format("%d / %d", mWepLoaded, mWepCap);
			row(c, big, col, (CANVAS_W - big.StringWidth(top)) / 2, 8, top);

			String res = String.Format("%d", mWepPool);
			if (sml) row(c, sml, Font.CR_UNTRANSLATED,
				(CANVAS_W - sml.StringWidth(res)) / 2, 36, res);
		}
		else
		{
			String top = String.Format("%d", mWepPool);
			row(c, big, col, (CANVAS_W - big.StringWidth(top)) / 2, 20, top);
		}
	}

	// Vitals plate:
	//   [mugshot]  health
	//              armor
	//              keys
	private ui void PaintVitals(String canvasName, TextureID mug)
	{
		let c = TexMan.GetCanvas(canvasName);
		if (!c) return;
		bed(c, canvasName);

		Font big = bigFont();
		if (!big) return;

		int x0 = 6;
		if (mug.IsValid())
		{
			icon(c, mug, 4, 6, 28, 34);
			x0 = 38;
		}

		TextureID med = TexMan.CheckForTexture("MEDIA0", TexMan.Type_Any, TexMan.TryAny);
		icon(c, med, x0, 4, 12, 12);
		row(c, big, Font.CR_UNTRANSLATED, x0 + 16, 4, String.Format("%d", mHealth));

		if (mArmor > 0)
		{
			icon(c, mArmorIcon, x0, 24, 12, 12);
			row(c, big, Font.CR_UNTRANSLATED, x0 + 16, 24, String.Format("%d", mArmor));
		}

		int kx = x0;
		for (int i = 0; i < mKeyIcons.Size() && i < 6; i++)
		{
			icon(c, mKeyIcons[i], kx, 46, 10, 14);
			kx += 12;
		}
	}
}


// =====================================================================
// RS_HandHUDRead -- READING SOMEBODY ELSE'S MAGAZINE.
//
// A mod that keeps a magazine keeps it in an int on its weapon class, and
// this package has no idea that class exists. The fork's reflection natives
// close that gap: level.GetFieldInt(obj, "name", out value) reads a field by
// NAME, so a list of the names mods actually use covers most of them without
// a compat reader per mod.
//
// The list is ordered by how unambiguous the name is. "mag" and "clip" are
// last because plenty of things are called that without being a count.
//
// CACHED PER CLASS, because the answer never changes for a class and the
// probe is a string compare per candidate. A class that answers nothing is
// cached too -- the miss is the expensive case and it is the common one.
//
// rs_handhud_magfield overrides the whole list with one name, which is how a
// mod the list does not cover gets read without a code change: run
// `netevent rs-handhud-probe`, read the field names off the console, put one
// in the cvar.
class RS_HandHUDRead
{
	// A LOOKUP FUNCTION, NOT AN ARRAY. ZScript's `static const X[]` takes
	// numeric types only, and a class may not hold a static member variable
	// at all -- so a list of names has to be a switch. Ordered by how
	// unambiguous the name is: "mag" and "clip" are last because plenty of
	// things are called that without being a count.
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

	// THREE SHAPES, AND A MOD PICKS ONE.
	//
	//   a FIELD on the weapon        modern ZScript. Read by name.
	//   Ammo2                        the classic ZDoom idiom, handled by the
	//                                caller before this is reached.
	//   an INVENTORY ITEM            DECORATE-era mods -- Project Brutality's
	//                                PumpshotgunMagazine and everything shaped
	//                                like it. No field exists to read.
	//
	// The third is the one that needs work, because nothing links the item to
	// the gun except the two names agreeing. See ItemMagazine.
	//
	// loaded, capacity. loaded < 0 means "nothing here knows".
	static int, int Magazine(Weapon w, PlayerInfo p)
	{
		if (!w || !level) return -1, 0;

		// The manual override wins outright, and answers with only a count --
		// a capacity of 0 makes the plate show the number on its own.
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

		// No field: try the inventory shape.
		let pmo = (w.Owner != null) ? PlayerPawn(w.Owner) : null;
		if (pmo)
		{
			int il, ic;
			[il, ic] = ItemMagazine(w, pmo);
			if (il >= 0) return il, ic;
		}
		return -1, 0;
	}

	// A MAGAZINE KEPT AS AN INVENTORY ITEM.
	//
	// Project Brutality counts the pump shotgun's shells in an item called
	// PumpshotgunMagazine sitting on the player; there is no field anywhere to
	// read and no compat reader could keep up with a mod that adds guns. What
	// IS reliable is that the two names agree -- the item is named after the
	// gun -- so the item can be found by matching them.
	//
	// THREE TESTS, and all three are needed:
	//
	//   1. the item's name ends in a magazine word.
	//   2. what is left when that word is removed appears in the weapon's own
	//      class name. PumpshotgunMagazine -> "pumpshotgun", which sits inside
	//      "pbpumpshotgun".
	//   3. IT CAN HOLD MORE THAN ONE. This is what separates a magazine from
	//      the flags these mods are full of -- PBPumpShotgunHasUnloaded,
	//      RevolverHasUnloaded, FlamerUnloaded are all MaxAmount 1, and every
	//      one of them ends in "loaded".
	//
	// MaxAmount doubles as the capacity, which is the number the mod already
	// had to declare for the item to work at all.
	static int, int ItemMagazine(Weapon w, PlayerPawn pmo)
	{
		if (!w || !pmo) return -1, 0;
		String wn = w.GetClassName();
		wn = Squash(wn);
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

			// Longest stem wins: "pumpshotgun" beats "shotgun" for a weapon
			// whose name contains both.
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
	// words first: "magazine" before "mag", or every magazine keeps an "azine".
	private static String MagStem(String n)
	{
		int c = MagWordCount();
		for (int i = 0; i < c; i++)
		{
			String word = MagWord(i);
			int at = n.IndexOf(word);
			if (at < 0) continue;
			if (at + word.Length() != n.Length()) continue;   // must END with it
			return n.Left(at);
		}
		return "";
	}

	private static int MagWordCount() { return 6; }
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

	// EVERY FIELD ON THE WEAPON, printed. The answer to "what does this mod
	// call its magazine" for a mod nobody has read the source of.
	static void Probe(Weapon w, String label)
	{
		if (!w) { Console.Printf("\cg[HandHUD probe] %s: no weapon", label); return; }
		Console.Printf("\cf[HandHUD probe] %s = %s", label, w.GetClassName());

		if (w.Ammo1)
			Console.Printf("   Ammo1  %-20s %d / %d", w.Ammo1.GetClassName(), w.Ammo1.Amount, w.Ammo1.MaxAmount);
		if (w.Ammo2)
			Console.Printf("   Ammo2  %-20s %d / %d", w.Ammo2.GetClassName(), w.Ammo2.Amount, w.Ammo2.MaxAmount);

		// The inventory shape, listed with the two things that decide it: an
		// item that can hold more than one, and whether its name matches this
		// weapon's. A mod using this shape shows its magazine here even when
		// the weapon itself has no field worth reading.
		let pmo = (w.Owner != null) ? PlayerPawn(w.Owner) : null;
		if (pmo)
		{
			int il, ic;
			[il, ic] = ItemMagazine(w, pmo);
			if (il >= 0) Console.Printf("\cd   matched inventory magazine: %d / %d", il, ic);

			Console.Printf("   inventory items that could be a magazine:");
			for (Inventory it = pmo.Inv; it != null; it = it.Inv)
			{
				if (it.MaxAmount <= 1 || Ammo(it)) continue;
				Console.Printf("      %-28s %d / %d", it.GetClassName(), it.Amount, it.MaxAmount);
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
				Console.Printf("      %-28s %-10s = %d", fname, ftype, v);
			else
				Console.Printf("      %-28s %-10s", fname, ftype);
		}
	}
}
