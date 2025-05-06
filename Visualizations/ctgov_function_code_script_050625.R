##############################################################################
### Name: Katrina Dobinda
### Description: CT.GOV AE Function Code
### Date Created:  10.18.2023
### Date Updated: 05.06.2024
### Updates:
### - Made SAE/AE code to be 0/1
### - Made naming simpler for column names
##############################################################################



# --------- Pre-processing Function ------ #

## This function will filter out baseline data (using an inputted cutoff date
## and ae_st_date), as well as rename two variables. It will default to using
## dt_consent if you do not specify a cutoff date
## If you do not wish to use this method for filtering
## out baseline, please manually filter out baseline and rename vars

## ae_data: Your final analysis dataset for the reporting you wish to complete 
## It must have variables of "ae_st_date", "ae_ctcae_cat", "ae_ctcae_term_value",
## "dt_consent" and "ptid"

## cutoff_dt: a variable holding cutoff dates for when ae's should have started
## to be included in reporting (defaulted to dt_consent)
## Please note that cutoff_dt and ae_st_date must be formatted as dates before
## inputted

## outputs a dataframe

pre_processing_ae_data <- function(ae_data, cutoff_dt = dt_consent){
  
  processed_data <- ae_data  %>% 
    
    # Filtering out AEs before date of consent (via correspondance with George)
    filter(ae_st_date >= {{cutoff_dt}})  %>%
    
    # Renaming 
    rename(organSystemName = ae_ctcae_cat, term = ae_ctcae_term_value)  
  
  return(processed_data)
}

# ------------ Single Arm Function ------- #

## processed_ae_data: your final analysis dataset for the reporting you wish to complete
## and it must have variables of "ae_ctcae_cat", "ae_ctcae_term_value",
## and "ptid"

## ptid_ae_evaluable: this is a vector of the patient IDS who are
## evaluable for the toxicity/safety endpoint, also defined as "participants 
## included in the assessment of adverse events (that is, the denominator for
## calculating frequency of adverse events)"

## trt_name = the name/identifier of the treatment for this arm, names column
## if end goal is to use export function, ensure that this matches the template

## sae_or_other = either "Serious" or "Other", for what type of ctgov AE report you want
## please note that other simply means not serious adverse event (non-SAE)

## You can filter your datasets within this function to input into the multi-arm
## function that will combine them together

## outputs a dataframe/tibble object

# --- SINGLE ARM -- #
ctgov_ae_tables_single_arm <- function(
    processed_ae_data, ptid_ae_evaluable, trt_name = "drug", sae_or_other = "Other"){
  
  # Prepping the dataset
  data <- processed_ae_data  %>%
    
    # Filtering to Toxicity Evaluable Patients
    filter(ptid %in% ptid_ae_evaluable)
  
  # Getting numSubjectsAtRisk
  numSubjectsAtRisk <- length(unique(data$ptid))
  #total sample size for toxicity evaluable patients
  
  if (sae_or_other == "Other") {
    # Other AEs Table (nonSAEs)
    ae_data_filtered <- data %>% filter(ae_sae %in% c(0, "No"))}
  
  else if (sae_or_other == "Serious") {
    # Serious AEs Table
    ae_data_filtered <- data %>% filter(ae_sae %in% c(1, "Yes")) }
  
  else {
    # Invalid Entry
    stop(
      paste("Invalid input for type.",
            "Please input either 'Other' or 'Serious' for the type input argument"))}
  
  # Getting numSubjectsAffected
  ae_ctgov_table <- ae_data_filtered %>%
    # Grouping by Patient and Terms
    group_by(ptid, organSystemName, term) %>%
    # Getting only one of each group (i.e. one count of unique event per patient)
    filter(row_number()==1) %>%
    # Groupiing by OrganSystem and term to summarise total count
    group_by(organSystemName, term) %>%
    summarise(!!paste0(trt_name, "{numSubjectsAffected}") := n()) %>%
    
    # Adding the remaining variables for the AE Table
    mutate(!!paste0(trt_name, "{numSubjectsAtRisk}") := numSubjectsAtRisk,
           adverseEventType = paste(sae_or_other),
           !!paste0(trt_name, "{numEvents}") := NA,
           assessmentType="Systematic Assessment",
           additionalDescription = NA,
           sourceVocabulary = NA)  %>%
    
    # Using Relocate for putting everything in the correct order
    relocate(organSystemName, .after = additionalDescription) %>%
    relocate(term,
             !!paste0(trt_name, "{numEvents}"),
             !!paste0(trt_name, "{numSubjectsAffected}"),
             !!paste0(trt_name, "{numSubjectsAtRisk}"),
             .after = sourceVocabulary) %>%
    ungroup()
  
  # If there are no adverse events, still adding numSubjectsatRisk for multi-arm 
  if (nrow(ae_ctgov_table) == 0){
    ae_ctgov_table <- ae_ctgov_table %>%
      add_row(!!paste0(trt_name, "{numSubjectsAtRisk}") := numSubjectsAtRisk)
  }
  
  return(ae_ctgov_table)
}

# ---------- Multi-Arm Function Variables ---------- #

## ae_arm_data_list: this is a list of all the ae_table you created by arm using
## the single arm function 
## ex: ae_arm_data_list <- list(arm1, arm2, arm3)

## ensure that the order of the list is the order of the arms on the template

## outputs a dataframe/tibble object

# --- MULTIPLE ARMS --- #
ctgov_ae_tables_multi_arm <- function(
    ae_arm_data_list){
  
  # Combining
  
  combined_ae <- ae_arm_data_list %>% reduce(full_join, by = 
                                               c("adverseEventType", 
                                                 "assessmentType" , 
                                                 "additionalDescription",
                                                 "organSystemName" , 
                                                 "sourceVocabulary" ,
                                                 "term"))
  
  # Cleaning up the Tables
  
  combined_ctgov_table <- combined_ae %>% 
    
    # Replace NAs with 0
    ungroup() %>% 
    mutate_at(vars(matches("numSubjectsAffected")), ~replace_na(.,0)) %>%
    
    # Fill in the missing parts of NumSubjectsAtRisk with itself
    fill(contains("Risk"), .direction = "downup") %>%
    
    # Removing rows that have NA term and category
    filter(!(is.na(organSystemName) & is.na(term))) %>%
    
    # Organizing location of variables  
    relocate(adverseEventType,
             assessmentType, 
             additionalDescription,
             organSystemName, 
             sourceVocabulary,
             term)
  
  return(combined_ctgov_table)
}

# ----------- Exporting to Template function ------------- #

## template_dir: the file folder of the template given for this study

## template_file: the file name of the template given for this study

## ae_tables: dataframe object that is formatted as a ctgov AE table
## (preferably created from the functions above)

## dir_out: the directory of the folder you wish the templates to be exported to

## study_number: a string of your study numner

## sae_or_other: either "serious" or "other" for what type of ctgov AE table
## please note that other simply means not serious adverse event (non-SAE)

exporting_xlsx_template <- function(
    template_dir,
    template_file,
    ctgov_ae_table,
    dir_out,
    study_number,
    sae_or_other) {
  
  # Making a new workbook 
  template_wb <- loadWorkbook(file.path(template_dir, template_file))
  
  # Pulling column names from template (without spacing)
  template_names <-  gsub(" ", "", as.character(readWorkbook(template_wb)[14,]))
    # template names are on the 14th row of the template file
  col_names <- gsub(" ", "", names(ctgov_ae_table))
  
  # Checking to see if column names match  
  if (identical(template_names, col_names)){
    
    # Adding in created template
    writeData(template_wb, sheet = 1, 
              ctgov_ae_table, startCol=1, 
              startRow=16, rowNames = FALSE,
    # start row is 16 due to template metadata - subject to change in the future
              colNames = FALSE)
    
    # Bolding the header column
    style <- createStyle(textDecoration = "bold")
    addStyle(template_wb, sheet = 1, style,
             rows = 15, cols = 1:ncol(ctgov_ae_table) ,gridExpand = TRUE)
    
    # Saving to excel file
    saveWorkbook(template_wb,
                 file.path(dir_out, paste("ctgov_",
                                          sae_or_other,
                                          "_adverse_events_",
                                          study_number,
                                          "_",
                                          gsub("/", "_",
                                               format(Sys.Date(), "%m/%d/%Y")),
                                          ".xlsx", sep="")),
                 overwrite = TRUE)
  }
  
  # If they do not match
  else {
    "Column names do not match template. Please check column names."
  }}

