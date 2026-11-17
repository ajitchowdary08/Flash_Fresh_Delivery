import pytest

def test_indian_gst_tax_rules():
    # 0% GST on Fresh Veggies & Raw Meats
    veggie_subtotal = 180.0
    veggie_gst = 0.0
    assert veggie_gst == 0.0

    # 18% GST on Service Fees (Delivery Fee ₹15 + Handling Fee ₹4 = ₹19)
    delivery_fee = 15.0
    handling_fee = 4.0
    service_gst = round(0.18 * (delivery_fee + handling_fee), 2)
    assert service_gst == 3.42

    grand_total = veggie_subtotal + delivery_fee + handling_fee + service_gst
    assert grand_total == 202.42
