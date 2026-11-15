"""Generate a Chen ER diagram from the entity and relationship definitions below.

Run with Python 3. DOT source is always written beside this script. If Graphviz
is installed, PNG and SVG versions are rendered as well.
"""

import argparse
from html import escape
import json
from pathlib import Path
import shutil
import subprocess

# + Entities: (key attribute, [other notable attributes], [derived attributes])
ent = {
  "Customer": ( "customer_id", ["email_address", "full_name", "phone_number",  "password_hash", "is_active", "created_at"], []),
  "Address": ("address_id", ["city", "state"], []),
  "Seller": ("seller_id", ["business_name", "commission_rate"], []),
    "Category": ("category_id", ["name"], []),
 "Brand": ("brand_id", ["name"], []),
 "Product": ("product_id", ["name", "status"], []),
 "Variant": ("variant_id", ["sku", "price"], []),
 "Inventory": ("variant_id", ["quantity_in_store"], ["available_qty"]),
 "Cart": ("cart_id", ["status"], []),
 "Coupon": ("coupon_id", ["code"], []),
 "Order": ("order_id", ["placed_at", "status"], ["total_amount"]),
 "Payment": ("payment_id", ["method", "status"], []),
 "Refund": ("refund_id", ["amount"], []),
 "Shipment": ("shipment_id", ["tracking_number"], []),
 "ShipmentEvent": ("event_id", ["event_time"], []),
 "Review": ("review_id", ["rating"], []),
 "Payout": ("payout_id", ["period_start", "period_end"], ["net_amount"]),
}


# _ Relationships: (relationship, left, left card, right, right card, [relationship attributes])


rel = [
   ("HAS","Customer","1","Address","N",[]),
 ("OWNS","Customer","1","Cart","N",[]),
 ("IN_CART","Cart","M","Variant","N",["quantity"]),
 ("PLACES","Customer","1","Order","N",[]),
 ("CONTAINS","Order","M","Variant","N",["quantity","unit_price"]),
 ("SHIPS_TO","Address","1","Order","N",[]),
 ("DISCOUNTS","Coupon","1","Order","N",[]),
 ("PAID_BY","Order","1","Payment","N",[]),
 ("REFUNDED_BY","Payment","1","Refund","N",[]),
 ("DELIVERED_IN","Order","1","Shipment","N",[]),
 ("FULFILS","Seller","1","Shipment","N",[]),
 ("TRACKED_BY","Shipment","1","ShipmentEvent","N",[]),
 ("LISTS","Seller","1","Product","N",[]),
 ("CLASSIFIES","Category","1","Product","N",[]),
 ("PARENT_OF","Category","1","Category","N",[]),
 ("BRANDS","Brand","1","Product","N",[]),
 ("HAS_VARIANT","Product","1","Variant","N",[]),
 ("STOCKED_AS","Variant","1","Inventory","1",[]),
 ("WRITES","Customer","1","Review","N",[]),
 ("RECEIVES","Product","1","Review","N",[]),
 ("PAID_OUT","Seller","1","Payout","N",[]),
]



