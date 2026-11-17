from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from app.core.config import settings
from app.models.models import Base, Category, Product, ProductVariant

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
        cat_chicken = get_or_create_cat("Sunday Fresh Chicken", "chicken", "egg", 5)
        cat_fish = get_or_create_cat("Sunday Fresh Fish & Seafood", "seafood", "water", 6)

        # Helper to add product if missing
        def add_prod(cat_id, name, desc, img, is_sunday, variants_data):
            existing = db.query(Product).filter(Product.name == name).first()
            if not existing:
                p = Product(
                    category_id=cat_id,
                    name=name,
                    description=desc,
                    image_url=img,
                    is_sunday_only=is_sunday
                )
                p.variants = [
                    ProductVariant(weight_label=v[0], mrp=v[1], price=v[2], stock_qty=v[3])
                    for v in variants_data
                ]
                db.add(p)
                db.commit()

        # 1. Daily Fresh Vegetables
        add_prod(cat_veggies.id, "Fresh Farm Hybrid Tomatoes", "Crisp, red, farm-fresh local tomatoes from Medak farms.", "https://images.unsplash.com/photo-1592924357228-91a4daadcfea?w=500&q=80", False, [("500g", 25.0, 18.0, 150), ("1kg", 50.0, 34.0, 100)])
        add_prod(cat_veggies.id, "Fresh Red Onions (Kurnool)", "Cleaned, pungent, premium grade onions.", "https://images.unsplash.com/photo-1618512496248-a07fe83aa8cb?w=500&q=80", False, [("1kg", 45.0, 36.0, 200), ("2kg (Saver Pack)", 90.0, 68.0, 80)])
        add_prod(cat_veggies.id, "New Crop Fresh Potatoes (Aloo)", "Firm, thin-skinned golden potatoes.", "https://images.unsplash.com/photo-1518977676601-b53f82aba655?w=500&q=80", False, [("1kg", 40.0, 32.0, 180), ("2kg", 80.0, 60.0, 90)])
        add_prod(cat_veggies.id, "Green Tender Ladies Finger (Bhendi)", "Freshly handpicked tender bhendi, perfect for fry.", "https://images.unsplash.com/photo-1625944525533-473f1a3d54e7?w=500&q=80", False, [("250g", 20.0, 15.0, 60), ("500g", 40.0, 28.0, 50)])
        add_prod(cat_veggies.id, "Fresh Ridge Gourd (Beerakaya)", "Tender, fiber-rich, fresh ridge gourd.", "https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=500&q=80", False, [("500g", 35.0, 26.0, 70)])
        add_prod(cat_veggies.id, "Tender Bottle Gourd (Sorakaya)", "Juicy, pale green bottle gourd.", "https://images.unsplash.com/photo-1603048588665-791ca8aea617?w=500&q=80", False, [("1 Unit (600g)", 30.0, 22.0, 50)])
        add_prod(cat_veggies.id, "Green Capsicum (Simla Mirchi)", "Crisp, glossy green bell peppers.", "https://images.unsplash.com/photo-1563565375-f3fdfdbefa83?w=500&q=80", False, [("250g", 25.0, 19.0, 80), ("500g", 50.0, 36.0, 40)])
        add_prod(cat_veggies.id, "Purple Brinjal / Eggplant (Vankaya)", "Tender, shiny purple brinjal for stuffed curries.", "https://images.unsplash.com/photo-1615485290382-441e4d049cb5?w=500&q=80", False, [("500g", 30.0, 22.0, 65)])
        add_prod(cat_veggies.id, "Fresh Green Peas (Matar)", "Sweet, tender green pea pods.", "https://images.unsplash.com/photo-1587735243615-c03f25aaff15?w=500&q=80", False, [("250g", 35.0, 26.0, 90), ("500g", 70.0, 48.0, 50)])
        add_prod(cat_veggies.id, "Fresh Bitter Gourd (Kakarakaya)", "Tender, dark green bitter gourd.", "https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=500&q=80", False, [("250g", 22.0, 16.0, 75), ("500g", 44.0, 30.0, 45)])
        add_prod(cat_veggies.id, "Fresh Cluster Beans (Goruchikkudu)", "Cleaned, tender green cluster beans.", "https://images.unsplash.com/photo-1625944525533-473f1a3d54e7?w=500&q=80", False, [("250g", 25.0, 18.0, 60)])
        add_prod(cat_veggies.id, "Fresh Tender Drumsticks (Munakkaya)", "Long, flavorful drumstick pods.", "https://images.unsplash.com/photo-1603048588665-791ca8aea617?w=500&q=80", False, [("3 Pcs Pack", 30.0, 22.0, 80)])

        # 2. Fresh Leafy Greens
        add_prod(cat_leafy.id, "Hydroponic Fresh Palak (Spinach)", "Tender baby spinach leaves, hydro-washed.", "https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=500&q=80", False, [("250g Bunch", 25.0, 18.0, 90)])
        add_prod(cat_leafy.id, "Fresh Coriander & Mint Combo", "Aromatic fresh kothimeera and pudina bunch.", "https://images.unsplash.com/photo-1596797038530-2c107229654b?w=500&q=80", False, [("1 Combo Bunch", 20.0, 15.0, 120)])
        add_prod(cat_leafy.id, "Fresh Methi Leaves (Menthi Kura)", "Cleaned, aromatic fenugreek leaves.", "https://images.unsplash.com/photo-1540420773420-3366772f4999?w=500&q=80", False, [("200g Bunch", 22.0, 16.0, 85)])
        add_prod(cat_leafy.id, "Fresh Curry Leaves (Karivepaku)", "Intensely fragrant green curry leaves.", "https://images.unsplash.com/photo-1615485290382-441e4d049cb5?w=500&q=80", False, [("100g Bunch", 15.0, 10.0, 150)])
        add_prod(cat_leafy.id, "Fresh Amaranthus (Thotakura)", "Tender green amaranthus leafy greens.", "https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=500&q=80", False, [("250g Bunch", 20.0, 14.0, 70)])
        add_prod(cat_leafy.id, "Fresh Spring Onions", "Crisp green spring onions with bulbs.", "https://images.unsplash.com/photo-1618512496248-a07fe83aa8cb?w=500&q=80", False, [("1 Bunch (200g)", 25.0, 18.0, 60)])

        # 3. Salad & Exotics
        add_prod(cat_exotics.id, "Hybrid Salad Cucumber (Kheera)", "Cool, crisp, thin-skinned cucumber.", "https://images.unsplash.com/photo-1449300079323-02e209d9d3a6?w=500&q=80", False, [("500g", 25.0, 18.0, 100)])
        add_prod(cat_exotics.id, "Orange Crunchy Carrots", "Sweet, crunchy orange carrots.", "https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=500&q=80", False, [("500g", 35.0, 26.0, 80)])
        add_prod(cat_exotics.id, "Fresh Cauliflower Gobhi", "Tight, clean, white cauliflower florets.", "https://images.unsplash.com/photo-1568584711075-3d021a7c3ca3?w=500&q=80", False, [("1 Head (500g)", 40.0, 29.0, 60)])
        add_prod(cat_exotics.id, "Fresh Green Cabbage", "Crisp, layered green cabbage.", "https://images.unsplash.com/photo-1568584711075-3d021a7c3ca3?w=500&q=80", False, [("1 Head (600g)", 30.0, 22.0, 70)])
        add_prod(cat_exotics.id, "Fresh Beetroot", "Deep red, sweet juicy beetroot.", "https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?w=500&q=80", False, [("500g", 30.0, 22.0, 80)])
        add_prod(cat_exotics.id, "Fresh Sweet Corn Cobs", "Sweet golden corn cobs.", "https://images.unsplash.com/photo-1551754655-cd27e38d2076?w=500&q=80", False, [("2 Pcs Pack", 35.0, 25.0, 90)])

        # 4. Kitchen Aromatics & Chilies
        add_prod(cat_aromatics.id, "Spicy Green Chillies (Pachi Mirchi)", "Fresh, pungent local green chillies.", "https://images.unsplash.com/photo-1588252303782-cb80119abd6d?w=500&q=80", False, [("100g", 15.0, 10.0, 140), ("250g", 35.0, 24.0, 90)])
        add_prod(cat_aromatics.id, "Fresh Ginger (Allam)", "Washed, pungent, fresh ginger roots.", "https://images.unsplash.com/photo-1615485290382-441e4d049cb5?w=500&q=80", False, [("250g", 30.0, 22.0, 110)])
        add_prod(cat_aromatics.id, "Native Garlic (Vellulli)", "Cleaned, aromatic garlic cloves.", "https://images.unsplash.com/photo-1540148426945-6cf22a6b2383?w=500&q=80", False, [("250g", 45.0, 35.0, 100)])
        add_prod(cat_aromatics.id, "Fresh Yellow Lemons (Nimmapakaya)", "Juicy, bright yellow lemons.", "https://images.unsplash.com/photo-1534706936160-d5ee67737249?w=500&q=80", False, [("4 Pcs Pack", 20.0, 15.0, 160)])

        # 5. Sunday Fresh Meat & Seafood
        add_prod(cat_chicken.id, "Sunday Special Tender Chicken (Curry Cut)", "100% antibiotic-free, freshly cut on Sunday morning.", "https://images.unsplash.com/photo-1604503468506-a8da13d82791?w=500&q=80", True, [("500g", 150.0, 125.0, 80), ("1kg", 290.0, 240.0, 50)])
        add_prod(cat_chicken.id, "Fresh Boneless Chicken Breast", "Cleaned, tender breast fillets.", "https://images.unsplash.com/photo-1607623814075-e51df1bdc82f?w=500&q=80", True, [("500g", 210.0, 175.0, 40)])
        add_prod(cat_fish.id, "Fresh Godavari Rohu Fish (Curry Cut)", "Fresh river fish, descaled and cut with head pieces.", "https://images.unsplash.com/photo-1534948216015-843149f72be3?w=500&q=80", True, [("500g", 220.0, 185.0, 30), ("1kg", 420.0, 360.0, 25)])
        add_prod(cat_fish.id, "Live Cleaned Sea Prawns (Medium)", "Deveined, peeled, juicy prawns.", "https://images.unsplash.com/photo-1559742811-822873691df8?w=500&q=80", True, [("250g", 230.0, 199.0, 20), ("500g", 440.0, 380.0, 15)])
        add_prod(cat_fish.id, "Fresh Tender Mutton Curry Cut", "Fresh tender goat meat, cut with bone for rich gravy.", "https://images.unsplash.com/photo-1603048588665-791ca8aea617?w=500&q=80", True, [("500g", 480.0, 420.0, 25), ("1kg", 950.0, 830.0, 15)])

    finally:
        db.close()
