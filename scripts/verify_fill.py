import sys
import os
import xml.etree.ElementTree as ET
import klayout.db as db

# ------------------------------------------------------------------
# CLI Argument Retrieval (-rd var=value)
# ------------------------------------------------------------------
if "input_a" not in globals() or "input_b" not in globals():
    print("ERROR: Missing required input arguments!")
    print("\nUsage:")
    print("  klayout -b -r verify_fill.py \\")
    print("    -rd input_a=base_design.gds \\")
    print("    -rd input_b=filled_design.gds \\")
    print("    -rd lyp=$PDK_ROOT/$PDK/libs.tech/klayout/tech/gf180mcu.lyp \\")
    print("    [-rd output=diff_result.gds] \\")
    print("    [-rd tolerance=0.001]")
    sys.exit(1)

out_gds = globals().get("output", "fill_diff.gds")
tol_um = float(globals().get("tolerance", 0.001))
lyp_file = globals().get("lyp", None)


def extract_dummy_layers_from_lyp(lyp_path: str) -> list[tuple[int, int]]:
    """Parses a KLayout .lyp XML file for layers containing 'fill' or 'dummy'."""
    expanded_path = os.path.expandvars(lyp_path)
    if not os.path.isfile(expanded_path):
        print(f"[ERROR] Specified LYP file not found: {expanded_path}")
        sys.exit(1)

    dummy_layers = []
    tree = ET.parse(expanded_path)
    root = tree.getroot()

    # Search all <properties> blocks in the XML tree
    for prop in root.findall(".//properties"):
        name_node = prop.find("name")
        source_node = prop.find("source")

        if source_node is not None and source_node.text:
            source_text = source_node.text.strip()
            name_text = name_node.text.strip() if (name_node is not None and name_node.text) else ""
            
            # Combine both strings for case-insensitive keyword search
            combined_descriptor = f"{name_text} {source_text}".lower()

            if "fill" in combined_descriptor or "dummy" in combined_descriptor:
                # Extracts "30/4" from "Poly2_Dummy 30/4@1" or "30/4@1"
                # Split by space first if name is embedded in source
                parts = source_text.split("@")[0].split()
                layer_datatype_str = parts[-1]  # Get the "30/4" portion

                if "/" in layer_datatype_str:
                    try:
                        lyr, dt = layer_datatype_str.split("/")
                        parsed_pair = (int(lyr), int(dt))
                        dummy_layers.append(parsed_pair)
                        
                        display_label = name_text if name_text else source_text
                        print(f"  [PDK Map] Found Dummy/Fill Layer: '{display_label}' -> ({lyr}/{dt})")
                    except ValueError:
                        continue

    parsed_layers = sorted(list(set(dummy_layers)))
    return parsed_layers


def verify_dummy_fill(
    original_gds: str,
    filled_gds: str,
    diff_out_gds: str,
    dummy_layers: list[tuple[int, int]],
    tolerance_um: float
) -> bool:
    print("\n--------------------------------------------------")
    print(f"File A (Original) : {original_gds}")
    print(f"File B (Filled)   : {filled_gds}")
    print(f"Output Diff File  : {diff_out_gds}")
    print(f"Tolerance         : {tolerance_um} um")
    print("--------------------------------------------------")

    layout_a = db.Layout()
    layout_a.read(original_gds)
    top_a = layout_a.top_cell()

    layout_b = db.Layout()
    layout_b.read(filled_gds)
    top_b = layout_b.top_cell()

    diff_layout = db.Layout()
    diff_layout.dbu = layout_a.dbu
    diff_top = diff_layout.create_cell("DIFF_TOP")

    layers_a = {(info.layer, info.datatype) for info in layout_a.layer_infos()}
    layers_b = {(info.layer, info.datatype) for info in layout_b.layer_infos()}
    all_layers = layers_a.union(layers_b)

    dummy_layer_set = set(dummy_layers)
    has_functional_violations = False
    dbu_tolerance = int(tolerance_um / layout_a.dbu)

    print("Running XOR verification across layers...")

    for layer_pair in sorted(all_layers):
        l, d = layer_pair
        is_dummy = layer_pair in dummy_layer_set

        l_idx_a = layout_a.find_layer(l, d)
        l_idx_b = layout_b.find_layer(l, d)

        region_a = db.Region(top_a.begin_shapes_rec(l_idx_a)) if l_idx_a != -1 else db.Region()
        region_b = db.Region(top_b.begin_shapes_rec(l_idx_b)) if l_idx_b != -1 else db.Region()

        # 1. XOR Operation
        raw_diff = region_a ^ region_b

        if raw_diff.is_empty():
            continue

        # 2. Sizing tolerance filter (undersize / oversize)
        filtered_diff = raw_diff.sized(-dbu_tolerance).sized(dbu_tolerance)

        if not filtered_diff.is_empty():
            if is_dummy:
                print(f"  [INFO] Valid changes detected on Dummy/Fill Layer ({l}/{d})")
            else:
                print(f"  [ERROR] VIOLATION: Differences found on Functional Layer ({l}/{d})!")
                has_functional_violations = True

            out_l_idx = diff_layout.insert_layer(db.LayerInfo(l, d))
            diff_top.shapes(out_l_idx).insert(filtered_diff)

    if has_functional_violations:
        print("\nRESULT: FAIL — Functional layers were modified!")
        print(f"Writing violation layout to: {diff_out_gds}")
        diff_layout.write(diff_out_gds)
        return False
    else:
        print("\nRESULT: OK — All geometric changes are strictly within PDK dummy/fill layers.")
        return True


# --- Main Execution ---
if lyp_file:
    print(f"Extracting dummy layers from LYP file: {lyp_file}")
    pdk_dummy_layers = extract_dummy_layers_from_lyp(lyp_file)
else:
    print("[WARNING] No LYP file provided. All differences will be flagged as violations.")
    pdk_dummy_layers = []

success = verify_dummy_fill(
    original_gds=input_a,
    filled_gds=input_b,
    diff_out_gds=out_gds,
    dummy_layers=pdk_dummy_layers,
    tolerance_um=tol_um
)

if not success:
    sys.exit(1)
