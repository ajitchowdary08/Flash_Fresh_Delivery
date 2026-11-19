from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from app.core.config import settings
from app.models.models import Base, Category, Product, ProductVariant, Rider, PromoCode, User

connect_args = {"check_same_thread": False} if settings.DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(settings.DATABASE_URL, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def init_db():
    Base.metadata.create_all(bind=engine)

    # Automatic additive migration: add columns that were introduced to
    # already-existing tables (users.role, promo_codes.usage_count, orders.updated_at,
    # riders.user_id, etc.) without dropping data. Compatible with SQLite & Postgres.
    from sqlalchemy import inspect, text
    try:
        inspector = inspect(engine)
        existing_tables = set(inspector.get_table_names())
        is_pg = engine.dialect.name == "postgresql"

        def add_column_if_missing(table_name, column_name, column_ddl):
            try:
                if inspector.has_table(table_name):
                    cols = [c["name"] for c in inspector.get_columns(table_name)]
                    if column_name not in cols:
                        with engine.begin() as conn:
                            if is_pg:
                                conn.execute(text(f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS {column_name} {column_ddl}"))
                            else:
                                conn.execute(text(f"ALTER TABLE {table_name} ADD COLUMN {column_name} {column_ddl}"))
            except Exception as ex:
                print(f"Migration: Could not add column {column_name} to {table_name}: {ex}")

        # Dynamic pass: inspect every model table and auto-add any missing columns
        for table_name, table in Base.metadata.tables.items():
            if table_name in existing_tables:
                try:
                    existing_cols = {c["name"] for c in inspector.get_columns(table_name)}
                    for col in table.columns:
                        if col.name not in existing_cols:
                            col_type = col.type.compile(engine.dialect)
                            if is_pg:
                                ddl = f"ALTER TABLE {table_name} ADD COLUMN IF NOT EXISTS {col.name} {col_type}"
                            else:
                                ddl = f"ALTER TABLE {table_name} ADD COLUMN {col.name} {col_type}"

                            if col.default is not None and hasattr(col.default, 'arg') and isinstance(col.default.arg, (int, float, str, bool)):
                                val = col.default.arg
                                if isinstance(val, bool):
                                    ddl += " DEFAULT TRUE" if (is_pg and val) else (" DEFAULT FALSE" if is_pg else (" DEFAULT 1" if val else " DEFAULT 0"))
                                elif isinstance(val, str):
                                    ddl += f" DEFAULT '{val}'"
                                else:
                                    ddl += f" DEFAULT {val}"

                            with engine.begin() as conn:
                                conn.execute(text(ddl))
                            print(f"Auto-migration: Added column {col.name} to {table_name}")
                except Exception as table_mig_ex:
                    print(f"Auto-migration check failed for {table_name}: {table_mig_ex}")

        # Explicit safety pass for known table schema additions
        # Promo codes table updates
        add_column_if_missing("promo_codes", "usage_count", "INTEGER DEFAULT 0")
        add_column_if_missing("promo_codes", "valid_from", "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
        add_column_if_missing("promo_codes", "valid_until", "TIMESTAMP")
        add_column_if_missing("promo_codes", "description", "VARCHAR DEFAULT ''")
        add_column_if_missing("promo_codes", "is_active", "BOOLEAN DEFAULT TRUE")
        add_column_if_missing("promo_codes", "discount_percent", "FLOAT DEFAULT 0.0")
        add_column_if_missing("promo_codes", "max_discount", "FLOAT DEFAULT 0.0")
        add_column_if_missing("promo_codes", "min_order", "FLOAT DEFAULT 0.0")

        # Users table updates
        add_column_if_missing("users", "role", "VARCHAR DEFAULT 'CUSTOMER'")
        add_column_if_missing("users", "is_active", "BOOLEAN DEFAULT TRUE")
        add_column_if_missing("users", "monthly_credit_limit", "FLOAT DEFAULT 5000.0")
        add_column_if_missing("users", "current_monthly_dues", "FLOAT DEFAULT 0.0")
        add_column_if_missing("users", "is_pay_later_active", "BOOLEAN DEFAULT TRUE")
        add_column_if_missing("users", "updated_at", "TIMESTAMP")

        # Orders table updates
        add_column_if_missing("orders", "updated_at", "TIMESTAMP")
        add_column_if_missing("orders", "rider_id", "VARCHAR")
        add_column_if_missing("orders", "rider_name", "VARCHAR")
        add_column_if_missing("orders", "rider_phone", "VARCHAR")
        add_column_if_missing("orders", "rider_vehicle", "VARCHAR")
        add_column_if_missing("orders", "rider_lat", "FLOAT")
        add_column_if_missing("orders", "rider_lng", "FLOAT")
        add_column_if_missing("orders", "freshness_rating", "INTEGER")
        add_column_if_missing("orders", "rider_rating", "INTEGER")
        add_column_if_missing("orders", "review_notes", "TEXT")
        add_column_if_missing("orders", "delivery_otp", "VARCHAR DEFAULT '4921'")
        add_column_if_missing("orders", "is_sunday_meat_order", "BOOLEAN DEFAULT FALSE")
        add_column_if_missing("orders", "scheduled_slot", "VARCHAR DEFAULT '10-15 Mins Quick Delivery'")
        add_column_if_missing("orders", "delivery_instructions", "VARCHAR DEFAULT ''")
        add_column_if_missing("orders", "idempotency_key", "VARCHAR")
        add_column_if_missing("orders", "cf_order_id", "VARCHAR")
        add_column_if_missing("orders", "payment_session_id", "VARCHAR")
        add_column_if_missing("orders", "pg_payment_id", "VARCHAR")

        # Riders table updates
        add_column_if_missing("riders", "user_id", "VARCHAR")
        add_column_if_missing("riders", "vehicle", "VARCHAR DEFAULT ''")
        add_column_if_missing("riders", "rating", "FLOAT DEFAULT 5.0")
        add_column_if_missing("riders", "is_online", "BOOLEAN DEFAULT FALSE")
        add_column_if_missing("riders", "is_active", "BOOLEAN DEFAULT TRUE")
        add_column_if_missing("riders", "current_lat", "FLOAT")
        add_column_if_missing("riders", "current_lng", "FLOAT")
        add_column_if_missing("riders", "today_earnings", "FLOAT DEFAULT 0.0")
        add_column_if_missing("riders", "completed_trips_today", "INTEGER DEFAULT 0")
        add_column_if_missing("riders", "cod_cash_in_hand", "FLOAT DEFAULT 0.0")
        add_column_if_missing("riders", "created_at", "TIMESTAMP")
        add_column_if_missing("riders", "updated_at", "TIMESTAMP")

        # Addresses table updates
        add_column_if_missing("addresses", "house_number", "VARCHAR DEFAULT ''")
        add_column_if_missing("addresses", "landmark", "VARCHAR DEFAULT ''")
        add_column_if_missing("addresses", "distance_km", "FLOAT DEFAULT 0.0")
        add_column_if_missing("addresses", "is_serviceable", "BOOLEAN DEFAULT TRUE")
        add_column_if_missing("addresses", "is_default", "BOOLEAN DEFAULT FALSE")
    except Exception as e:
        print(f"Migration error during init_db: {e}")

    db = SessionLocal()
    try:
        # Helper to get or create category
        def get_or_create_cat(name: str, slug: str, icon: str, order: int):
            cat = db.query(Category).filter(Category.slug == slug).first()
            if not cat:
                cat = Category(name=name, slug=slug, icon=icon, display_order=order)
                db.add(cat)
                db.commit()
                db.refresh(cat)
            return cat

        cat_veggies = get_or_create_cat("Daily Fresh Vegetables", "vegetables", "carrot", 1)
        cat_leafy = get_or_create_cat("Fresh Greens & Leafy", "greens", "leaf", 2)
        cat_exotics = get_or_create_cat("Salad & Exotics", "exotics", "lemon", 3)
        cat_aromatics = get_or_create_cat("Kitchen Aromatics & Chilies", "aromatics", "pepper", 4)
        cat_milk = get_or_create_cat("Fresh Farm Milk & Dairy", "milk", "bottle", 5)
        cat_eggs = get_or_create_cat("Fresh Farm White Eggs", "eggs", "egg", 6)
        cat_chicken = get_or_create_cat("Sunday Fresh Chicken", "chicken", "egg", 7)
        cat_fish = get_or_create_cat("Sunday Fresh Fish & Seafood", "seafood", "water", 8)

        # Seed initial catalog products without overwriting admin price/stock edits on server restart
        def sync_prod(cat_id, name, desc, img, is_sunday, variants_data):
            p = db.query(Product).filter(Product.name == name).first()
            if not p:
                p = Product(
                    category_id=cat_id,
                    name=name,
                    description=desc,
                    image_url=img,
                    is_sunday_only=is_sunday,
                    is_active=True
                )
                db.add(p)
                db.commit()
                db.refresh(p)

                # Create initial default variants for brand-new products
                p.variants = [
                    ProductVariant(weight_label=v[0], mrp=v[1], price=v[2], stock_qty=v[3])
                    for v in variants_data
                ]
                db.commit()
            else:
                # Product already exists! DO NOT overwrite admin prices or delete variants!
                # Only populate variants if the product has none in DB
                existing_variants = db.query(ProductVariant).filter(ProductVariant.product_id == p.id).all()
                if not existing_variants:
                    p.variants = [
                        ProductVariant(weight_label=v[0], mrp=v[1], price=v[2], stock_qty=v[3])
                        for v in variants_data
                    ]
                    db.commit()
                # Update image if missing
                if not p.image_url and img:
                    p.image_url = img
                    db.commit()

        # Delete any removed egg products (Country Eggs, Brown Eggs)
        db.query(Product).filter(Product.name.like("%Country Eggs%")).delete(synchronize_session=False)
        db.query(Product).filter(Product.name.like("%Brown Protein%")).delete(synchronize_session=False)
        db.commit()

        # 1. Daily Fresh Vegetables (Accurate Verified Images)
        sync_prod(cat_veggies.id, "Fresh Farm Hybrid Tomatoes", "Crisp, red, farm-fresh local tomatoes.", "https://ik.imagekit.io/Ganapathi/tomato_600x600.jpg", False, [("500g", 25.0, 18.0, 150), ("1kg", 50.0, 34.0, 100)])
        sync_prod(cat_veggies.id, "Fresh Red Onions (Kurnool)", "Cleaned, premium grade red onions.", "https://ik.imagekit.io/Ganapathi/onion_600x600.jpg", False, [("1kg", 45.0, 36.0, 200), ("2kg (Saver Pack)", 90.0, 68.0, 80)])
        sync_prod(cat_veggies.id, "New Crop Fresh Potatoes (Aloo)", "Firm, thin-skinned golden potatoes.", "https://ik.imagekit.io/Ganapathi/potato_600x600.jpg", False, [("1kg", 40.0, 32.0, 180), ("2kg", 80.0, 60.0, 90)])
        sync_prod(cat_veggies.id, "Green Tender Ladies Finger (Bhendi)", "Freshly handpicked tender bhendi.", "https://ik.imagekit.io/Ganapathi/flash_fresh_green_tender_ladies_finger_bhendi_600x600.jpg", False, [("250g", 20.0, 15.0, 60), ("500g", 40.0, 28.0, 50)])
        sync_prod(cat_veggies.id, "Fresh Ridge Gourd (Beerakaya)", "Tender, fiber-rich ridge gourd.", "https://ik.imagekit.io/Ganapathi/flash_fresh_ridge_gourd_beerakaya_600x600.jpg", False, [("500g", 35.0, 26.0, 70)])
        sync_prod(cat_veggies.id, "Tender Bottle Gourd (Sorakaya)", "Juicy, pale green bottle gourd.", "https://ik.imagekit.io/Ganapathi/flash_fresh_bottle_gourd_sorakaya_600x600.jpg", False, [("1 Unit (600g)", 30.0, 22.0, 50)])
        sync_prod(cat_veggies.id, "Green Capsicum (Simla Mirchi)", "Crisp, glossy green bell peppers.", "https://ik.imagekit.io/Ganapathi/flash_fresh_green_capsicum_simla_mirchi_600x600.jpg", False, [("250g", 25.0, 19.0, 80), ("500g", 50.0, 36.0, 40)])
        sync_prod(cat_veggies.id, "Purple Brinjal (Vankaya)", "Tender, shiny purple brinjal.", "https://ik.imagekit.io/Ganapathi/brinjal_600x600.jpg", False, [("500g", 30.0, 22.0, 65)])
        sync_prod(cat_veggies.id, "Fresh Green Peas (Matar)", "Sweet, tender green pea pods.", "https://ik.imagekit.io/Ganapathi/flash_fresh_green_peas_matar_600x600.jpg", False, [("250g", 35.0, 26.0, 90), ("500g", 70.0, 48.0, 50)])
        sync_prod(cat_veggies.id, "Fresh Bitter Gourd (Kakarakaya)", "Tender, dark green bitter gourd.", "https://ik.imagekit.io/Ganapathi/flash_fresh_bitter_gourd_kakarakaya_600x600.jpg", False, [("250g", 22.0, 16.0, 75), ("500g", 44.0, 30.0, 45)])
        sync_prod(cat_veggies.id, "Fresh French Beans (Fasli)", "Cleaned, tender green french beans.", "https://ik.imagekit.io/Ganapathi/flash_fresh_french_beans_fasli_600x600.jpg", False, [("250g", 25.0, 18.0, 80)])
        sync_prod(cat_veggies.id, "Fresh Tender Drumsticks (Munakkaya)", "Long, flavorful drumstick pods.", "https://ik.imagekit.io/Ganapathi/flash_fresh_drumsticks_munakkaya_600x600.jpg", False, [("3 Pcs Pack", 30.0, 22.0, 80)])
        sync_prod(cat_veggies.id, "Fresh Raw Banana (Aratikaya)", "Green raw banana for curry & fry.", "https://ik.imagekit.io/Ganapathi/flash_fresh_raw_banana_aratikaya_600x600.jpg", False, [("2 Pcs Pack", 20.0, 15.0, 90)])
        sync_prod(cat_veggies.id, "Fresh Sweet Potato (Chilagada Dumpa)", "Sweet golden-red sweet potatoes.", "https://ik.imagekit.io/Ganapathi/flash_fresh_sweet_potato_chilagada_dumpa_600x600.jpg", False, [("500g", 35.0, 26.0, 70)])
        sync_prod(cat_veggies.id, "Fresh Colocasia / Arbi (Chama Dumpa)", "Cleaned root arbi for crispy fry.", "https://ik.imagekit.io/Ganapathi/flash_fresh_colocasia_arbi_chama_dumpa_600x600.jpg", False, [("500g", 40.0, 29.0, 60)])

        # 2. Fresh Greens & Leafy
        sync_prod(cat_leafy.id, "Hydroponic Fresh Palak (Spinach)", "Tender baby spinach leaves.", "https://ik.imagekit.io/Ganapathi/flash_fresh_hydroponic_fresh_palak_spinach_600x600.jpg", False, [("250g Bunch", 25.0, 18.0, 90)])
        sync_prod(cat_leafy.id, "Fresh Coriander & Mint Combo", "Aromatic fresh kothimeera and pudina.", "https://ik.imagekit.io/Ganapathi/flash_fresh_coriander_mint_combo_600x600.jpg", False, [("1 Combo Bunch", 20.0, 15.0, 120)])
        sync_prod(cat_leafy.id, "Fresh Methi Leaves (Menthi Kura)", "Cleaned, aromatic fenugreek leaves.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_methi_leaves_menthi_kura_600x600.jpg", False, [("200g Bunch", 22.0, 16.0, 85)])
        sync_prod(cat_leafy.id, "Fresh Curry Leaves (Karivepaku)", "Intensely fragrant green curry leaves.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_curry_leaves_karivepaku_600x600.jpg", False, [("100g Bunch", 15.0, 10.0, 150)])
        sync_prod(cat_leafy.id, "Fresh Amaranthus (Thotakura)", "Tender green amaranthus leafy greens.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_amaranthus_thotakura_600x600.jpg", False, [("250g Bunch", 20.0, 14.0, 70)])
        sync_prod(cat_leafy.id, "Fresh Spring Onions", "Crisp green spring onions with bulbs.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_spring_onions_600x600.jpg", False, [("1 Bunch (200g)", 25.0, 18.0, 60)])

        # 3. Salad & Exotics
        sync_prod(cat_exotics.id, "Hybrid Salad Cucumber (Kheera)", "Cool, crisp, thin-skinned cucumber.", "https://ik.imagekit.io/Ganapathi/flash_fresh_hybrid_salad_cucumber_kheera_600x600.jpg", False, [("500g", 25.0, 18.0, 100)])
        sync_prod(cat_exotics.id, "Orange Crunchy Carrots", "Sweet, crunchy orange carrots.", "https://ik.imagekit.io/Ganapathi/flash_fresh_orange_crunchy_carrots_600x600.jpg", False, [("500g", 35.0, 26.0, 80)])
        sync_prod(cat_exotics.id, "Fresh Cauliflower Gobhi", "Tight, clean, white cauliflower florets.", "https://ik.imagekit.io/Ganapathi/cauliflower_600x600.jpg", False, [("1 Head (500g)", 40.0, 29.0, 60)])
        sync_prod(cat_exotics.id, "Fresh Green Cabbage", "Crisp, layered green cabbage.", "https://ik.imagekit.io/Ganapathi/cabbage_600x600.jpg", False, [("1 Head (600g)", 30.0, 22.0, 70)])
        sync_prod(cat_exotics.id, "Fresh Beetroot", "Deep red, sweet juicy beetroot.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_beetroot_600x600.jpg", False, [("500g", 30.0, 22.0, 80)])
        sync_prod(cat_exotics.id, "Fresh Red Radish (Mulli)", "Crisp, peppery red radishes.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_red_radish_mulli_600x600.jpg", False, [("500g", 25.0, 18.0, 70)])
        sync_prod(cat_exotics.id, "Fresh Sweet Corn Cobs", "Sweet golden corn cobs.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_sweet_corn_cobs_600x600.jpg", False, [("2 Pcs Pack", 35.0, 25.0, 90)])
        sync_prod(cat_exotics.id, "Fresh Exotic Broccoli", "Tender green broccoli florets.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_exotic_broccoli_600x600.jpg", False, [("250g Pack", 60.0, 45.0, 50)])
        sync_prod(cat_exotics.id, "Fresh Button Mushrooms", "Cleaned white button mushrooms.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_button_mushrooms_600x600.jpg", False, [("200g Pack", 55.0, 42.0, 60)])

        # 4. Kitchen Aromatics & Chilies
        sync_prod(cat_aromatics.id, "Spicy Green Chillies (Pachi Mirchi)", "Fresh, pungent local green chillies.", "https://ik.imagekit.io/Ganapathi/flash_fresh_spicy_green_chillies_pachi_mirchi_600x600.jpg", False, [("100g", 15.0, 10.0, 140), ("250g", 35.0, 24.0, 90)])
        sync_prod(cat_aromatics.id, "Fresh Ginger (Allam)", "Washed, pungent, fresh ginger roots.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_ginger_allam_600x600.jpg", False, [("250g", 30.0, 22.0, 110)])
        sync_prod(cat_aromatics.id, "Native Garlic (Vellulli)", "Cleaned, aromatic garlic cloves.", "https://ik.imagekit.io/Ganapathi/flash_fresh_native_garlic_vellulli_600x600.jpg", False, [("250g", 45.0, 35.0, 100)])
        sync_prod(cat_aromatics.id, "Fresh Yellow Lemons (Nimmapakaya)", "Juicy, bright yellow lemons.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_yellow_lemons_nimmapakaya_600x600.jpg", False, [("4 Pcs Pack", 20.0, 15.0, 160)])

        # 5. Fresh Farm Milk & Dairy
        sync_prod(cat_milk.id, "Fresh Farm Cow Milk", "Pure, fresh cow milk, pasteurized & chilled.", "https://ik.imagekit.io/Ganapathi/flash_fresh_cow_milk_600x600.jpg", False, [("500ml", 30.0, 26.0, 200), ("1 Litre", 60.0, 50.0, 150)])
        sync_prod(cat_milk.id, "Pure Buffalo Milk", "Thick, creamy pure buffalo milk.", "https://ik.imagekit.io/Ganapathi/flash_fresh_buffalo_milk_600x600.jpg", False, [("500ml", 38.0, 32.0, 180), ("1 Litre", 75.0, 62.0, 120)])

        # 6. ONLY White Hen Eggs (Half Dozen, 1 Dozen & Saver Tray)
        sync_prod(cat_eggs.id, "Farm Fresh Table White Hen Eggs", "Protein-rich, farm-fresh white hen eggs.", "https://ik.imagekit.io/Ganapathi/flash_fresh_farm_fresh_table_white_hen_eggs_600x600.jpg", False, [("Half Dozen", 45.0, 36.0, 150), ("1 Dozen", 90.0, 68.0, 100), ("Saver Tray (30 Pcs)", 225.0, 165.0, 40)])

        # 7. Sunday Fresh Meat & Seafood
        sync_prod(cat_chicken.id, "Sunday Special Tender Chicken (Curry Cut)", "100% antibiotic-free, freshly cut on Sunday morning.", "https://ik.imagekit.io/Ganapathi/flash_fresh_sunday_special_tender_chicken_curry_cut_600x600.jpg", True, [("500g", 150.0, 125.0, 80), ("1kg", 290.0, 240.0, 50)])
        sync_prod(cat_chicken.id, "Fresh Boneless Chicken Breast", "Cleaned, tender breast fillets.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_boneless_chicken_breast_600x600.jpg", True, [("500g", 210.0, 175.0, 40)])
        sync_prod(cat_fish.id, "Fresh Godavari Rohu Fish (Curry Cut)", "Fresh river fish, descaled and cut with head pieces.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_godavari_rohu_fish_curry_cut_600x600.jpg", True, [("500g", 220.0, 185.0, 30), ("1kg", 420.0, 360.0, 25)])
        sync_prod(cat_fish.id, "Live Cleaned Sea Prawns (Medium)", "Deveined, peeled, juicy prawns.", "https://ik.imagekit.io/Ganapathi/flash_fresh_live_cleaned_sea_prawns_medium_600x600.jpg", True, [("250g", 230.0, 199.0, 20), ("500g", 440.0, 380.0, 15)])
        sync_prod(cat_fish.id, "Fresh Tender Mutton Curry Cut", "Fresh tender goat meat, cut with bone for rich gravy.", "https://ik.imagekit.io/Ganapathi/flash_fresh_fresh_tender_mutton_curry_cut_600x600.jpg", True, [("500g", 480.0, 420.0, 25), ("1kg", 950.0, 830.0, 15)])

        # ----------------------------------------------------------------------
        # Seed the delivery fleet (previously a hardcoded Python list).
        # Idempotent: only creates riders that don't already exist by phone.
        # ----------------------------------------------------------------------
        from app.models.models import Rider, PromoCode, User as UserModel

        def get_or_create_rider(phone, name, vehicle):
            r = db.query(Rider).filter(Rider.phone == phone).first()
            if r:
                return r
            # Mirror the rider as a User row (role=RIDER) so the OTP/JWT auth
            # flow used by customers also works for riders — same code path.
            u = db.query(UserModel).filter(UserModel.phone == phone).first()
            if not u:
                u = UserModel(id=f"rdr_{phone}", phone=phone, name=name, role="RIDER")
                db.add(u)
                db.commit()
                db.refresh(u)
            r = Rider(
                id=f"rdr_{phone}",
                phone=phone,
                name=name,
                vehicle=vehicle,
                rating=4.9,
                is_online=False,
                is_active=True,
                user_id=u.id,
            )
            db.add(r)
            db.commit()
            db.refresh(r)
            return r

        get_or_create_rider("9848012345", "Ravi Kumar", "Hero Electric (TS 07 EK 4921)")
        get_or_create_rider("9876524680", "Suresh Goud", "Ather 450X (TS 08 FA 1024)")
        get_or_create_rider("9123456789", "Naresh Krishna", "Ola S1 Pro (TS 07 AB 9988)")

        # ----------------------------------------------------------------------
        # Seed promo codes (previously a hardcoded Python dict in catalog.py).
        # ----------------------------------------------------------------------
        def get_or_create_promo(code, desc, pct, mx, mn):
            try:
                p = db.query(PromoCode).filter(PromoCode.code == code).first()
                if p:
                    return p
                p = PromoCode(
                    code=code,
                    description=desc,
                    discount_percent=pct,
                    max_discount=mx,
                    min_order=mn,
                    is_active=True,
                )
                db.add(p)
                db.commit()
                db.refresh(p)
                return p
            except Exception as pe:
                db.rollback()
                print(f"Warning: Could not seed promo code {code}: {pe}")
                return None

        get_or_create_promo("ZEPTO50", "Flat 20% OFF up to ₹50 on orders above ₹149", 20.0, 50.0, 149.0)
        get_or_create_promo("FLASH100", "Flat 25% OFF up to ₹100 on Flash Mega Orders above ₹299", 25.0, 100.0, 299.0)
        get_or_create_promo("SUNDAYMEAT", "Special 15% OFF on Sunday Fresh Meat & Seafood", 15.0, 75.0, 199.0)

        # ----------------------------------------------------------------------
        # Seed a default store-manager account (role=MANAGER). In production the
        # manager logs in via OTP on this number. Default creds surfaced in the
        # README. Idempotent.
        # ----------------------------------------------------------------------
        try:
            mgr = db.query(UserModel).filter(UserModel.phone == "9000011111").first()
            if not mgr:
                mgr = UserModel(
                    id="mgr_default_01",
                    phone="9000011111",
                    name="Store Manager",
                    role="MANAGER",
                    is_active=True,
                )
                db.add(mgr)
                db.commit()
        except Exception as me:
            db.rollback()
            print(f"Warning: Could not seed default manager: {me}")

    finally:
        db.close()
