# The top-level Makefile which builds everything

ASCIIDOC_DIR = documentation/asciidoc
HTML_DIR = documentation/html
IMAGES_DIR = documentation/images
JEKYLL_ASSETS_DIR = jekyll-assets
SCRIPTS_DIR = scripts
DOCUMENTATION_REDIRECTS_DIR = documentation/redirects
DOCUMENTATION_INDEX = documentation/index.json
SITE_CONFIG = _config.yml

BUILD_DIR = build
ASCIIDOC_BUILD_DIR = $(BUILD_DIR)/jekyll
ASCIIDOC_INCLUDES_DIR = $(BUILD_DIR)/adoc_includes
AUTO_NINJABUILD = $(BUILD_DIR)/autogenerated.ninja

PICO_SDK_DIR = lib/pico-sdk
PICO_EXAMPLES_DIR = lib/pico-examples
ALL_SUBMODULE_CMAKELISTS = $(PICO_SDK_DIR)/CMakeLists.txt $(PICO_EXAMPLES_DIR)/CMakeLists.txt
DOXYGEN_PICO_SDK_BUILD_DIR = build-pico-sdk-docs
DOXYGEN_XML_DIR = $(DOXYGEN_PICO_SDK_BUILD_DIR)/combined/docs/doxygen/xml
# The pico-sdk here needs to match up with the "from_json" entry in index.json
ASCIIDOC_DOXYGEN_DIR = $(ASCIIDOC_DIR)/pico-sdk

JEKYLL_CMD = bundle exec jekyll

.DEFAULT_GOAL := html

.PHONY: clean run_ninja clean_ninja html serve_html clean_html build_doxygen_xml clean_doxygen_xml build_doxygen_adoc clean_doxygen_adoc fetch_submodules clean_submodules clean_everything

$(BUILD_DIR):
	@mkdir -p $@

$(DOXYGEN_PICO_SDK_BUILD_DIR):
	mkdir $@

$(ASCIIDOC_DOXYGEN_DIR): | $(ASCIIDOC_DIR)
	mkdir $@

# Delete all autogenerated files
clean: clean_html clean_doxygen_adoc
	rm -rf $(BUILD_DIR)

# Initialise pico-sdk submodule (and the subnmodules that it uses)
$(PICO_SDK_DIR)/CMakeLists.txt $(PICO_SDK_DIR)/docs/index.h: | $(PICO_SDK_DIR)
	git submodule update --init $(PICO_SDK_DIR)
	git -C $(PICO_SDK_DIR) submodule update --init

# Initialise pico-examples submodule
$(PICO_EXAMPLES_DIR)/CMakeLists.txt: | $(PICO_SDK_DIR)/CMakeLists.txt $(PICO_EXAMPLES_DIR)
	git submodule update --init $(PICO_EXAMPLES_DIR)

# Initialise doxygentoasciidoc submodule
doxygentoasciidoc/__main__.py:
	git submodule update --init doxygentoasciidoc

fetch_submodules: $(ALL_SUBMODULE_CMAKELISTS) doxygentoasciidoc/__main__.py

# Get rid of the submodules
clean_submodules:
	git submodule deinit --all

# Create the pico-sdk Doxygen XML files
$(DOXYGEN_XML_DIR) $(DOXYGEN_XML_DIR)/index.xml: | $(ALL_SUBMODULE_CMAKELISTS) $(DOXYGEN_PICO_SDK_BUILD_DIR)
	cmake -S $(PICO_SDK_DIR) -B $(DOXYGEN_PICO_SDK_BUILD_DIR)/combined -D PICO_EXAMPLES_PATH=../../$(PICO_EXAMPLES_DIR) -D PICO_PLATFORM=combined-docs
	cmake -S $(PICO_SDK_DIR) -B $(DOXYGEN_PICO_SDK_BUILD_DIR)/PICO_RP2040 -D PICO_EXAMPLES_PATH=../../$(PICO_EXAMPLES_DIR) -D PICO_PLATFORM=rp2040
	cmake -S $(PICO_SDK_DIR) -B $(DOXYGEN_PICO_SDK_BUILD_DIR)/PICO_RP2350 -D PICO_EXAMPLES_PATH=../../$(PICO_EXAMPLES_DIR) -D PICO_PLATFORM=rp2350
	$(MAKE) -C $(DOXYGEN_PICO_SDK_BUILD_DIR)/combined docs
	$(MAKE) -C $(DOXYGEN_PICO_SDK_BUILD_DIR)/PICO_RP2040 docs
	$(MAKE) -C $(DOXYGEN_PICO_SDK_BUILD_DIR)/PICO_RP2350 docs
	python3 $(SCRIPTS_DIR)/postprocess_doxygen_xml.py $(DOXYGEN_PICO_SDK_BUILD_DIR)

$(DOXYGEN_PICO_SDK_BUILD_DIR)/combined/docs/Doxyfile: | $(DOXYGEN_XML_DIR)

build_doxygen_xml: | $(DOXYGEN_XML_DIR)

# Clean all the Doxygen HTML files
clean_doxygen_xml:
	rm -rf $(DOXYGEN_PICO_SDK_BUILD_DIR)

# create the sdk adoc and the json file
$(ASCIIDOC_DOXYGEN_DIR)/picosdk_index.json $(ASCIIDOC_DOXYGEN_DIR)/index_doxygen.adoc: $(ASCIIDOC_DOXYGEN_DIR) $(DOXYGEN_XML_DIR)/index.xml doxygentoasciidoc/__main__.py doxygentoasciidoc/cli.py doxygentoasciidoc/nodes.py doxygentoasciidoc/helpers.py | $(BUILD_DIR)
	$(MAKE) clean_ninja
	python3 -m doxygentoasciidoc -f $(DOXYGEN_XML_DIR)/index.xml > $(ASCIIDOC_DOXYGEN_DIR)/all_groups.adoc
	python3 -m doxygentoasciidoc -f $(DOXYGEN_XML_DIR)/indexpage.xml -c > $(ASCIIDOC_DOXYGEN_DIR)/index_doxygen.adoc
	python3 -m doxygentoasciidoc -f $(DOXYGEN_XML_DIR)/examples_page.xml -c > $(ASCIIDOC_DOXYGEN_DIR)/examples_page.adoc
	python3 $(SCRIPTS_DIR)/postprocess_doxygen_adoc.py $(ASCIIDOC_DOXYGEN_DIR)
	-cp $(DOXYGEN_XML_DIR)/*.png $(ASCIIDOC_DOXYGEN_DIR) 2>/dev/null || true

build_doxygen_adoc: $(ASCIIDOC_DOXYGEN_DIR)/index_doxygen.adoc

# Clean all the Doxygen asciidoc files
clean_doxygen_adoc:
	if [ -d $(ASCIIDOC_DOXYGEN_DIR) ]; then $(MAKE) clean_ninja; fi
	rm -rf $(ASCIIDOC_DOXYGEN_DIR)

clean_everything: clean_submodules clean_doxygen_xml clean

# AUTO_NINJABUILD contains all the parts of the ninjabuild where the rules themselves depend on other files
$(AUTO_NINJABUILD): $(SCRIPTS_DIR)/create_auto_ninjabuild.py $(DOCUMENTATION_INDEX) $(SITE_CONFIG) | $(BUILD_DIR)
	$< $(DOCUMENTATION_INDEX) $(SITE_CONFIG) $(ASCIIDOC_DIR) $(SCRIPTS_DIR) $(ASCIIDOC_BUILD_DIR) $(ASCIIDOC_INCLUDES_DIR) $(JEKYLL_ASSETS_DIR) $(DOXYGEN_PICO_SDK_BUILD_DIR) $(DOCUMENTATION_REDIRECTS_DIR) $(IMAGES_DIR) $@

# This runs ninjabuild to build everything in the ASCIIDOC_BUILD_DIR (and ASCIIDOC_INCLUDES_DIR)
run_ninja: $(AUTO_NINJABUILD)
	ninja

# Delete all the files created by the 'run_ninja' target
clean_ninja:
	rm -rf $(ASCIIDOC_BUILD_DIR)
	rm -rf $(ASCIIDOC_INCLUDES_DIR)
	rm -f $(AUTO_NINJABUILD)

# Build the html output files
html: run_ninja
	$(JEKYLL_CMD) build

# Build the html output files and additionally run a small webserver for local previews
serve_html: run_ninja
	$(JEKYLL_CMD) serve

# Delete all the files created by the 'html' target
clean_html:
	rm -rf $(HTML_DIR)
