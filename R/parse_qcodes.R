#' Parse coded text
#'
#' Take a text document containing coded text of the form:
#' "stuff to ignore (QCODE) coded text we care about (/QCODE){#qcode} more stuff to ignore"
#' and turn it into a dataframe with one row per coded item, of the form:
#' docid,qcode,text
#'
#' Replaces newline characters with "<br>" in the captured text
#' returns an empty dataframe (no rows) if no qcodes were found.
#'
#' @param x A data frame containing the text to be coded; requires columns "doc_id" and "document_text"
#' @param ...  Other parameters optionally passed in
#' @export

parse_qcodes <- function(x, ...){
  dots <- list(...)

  #replace all newlines in the document texts
  x$document_text <- stringr::str_replace_all(x$document_text, "[\r\n]", "<br>")

  #initialise the empty data frame to fill & return
  df <- data.frame(doc = integer(), qcode = factor(),
                   text = character(), stringsAsFactors = FALSE)

  ###iterate through each document submitted
  for (j in 1:nrow(x)) {
    doc <- x[j,]
     df <- parse_one_document(doc, df, dots)

  }

  return(df)

}

#' Check for coding errors
#' Checks the current document for coding errors.
#'
#' @param document The document to be scanned for errors.
#'
#' @export
error_check <- function(document) {
    ### basic tag error checking
    #check whether there are an equal number of (QCODE) and (/QCODE) tags
    open  = unlist( stringr::str_extract_all( document,"(\\(QCODE\\))"))
    close = unlist( stringr::str_extract_all( document,"(\\(/QCODE\\))"))
    if(length(open) != length(close)){
      warning("WARNING: number of (QCODE) and (/QCODE) tags do not match
              in document ; erroneous output is likely.\n")
    }
    #check whether there is a (/QCODE) tag missing its {#code}
    close = unlist( stringr::str_extract_all( document,
                                              "(\\(/QCODE\\)[^\\}]*?\\})"))
    for(tag in close){
      if( !stringr::str_detect(tag, "\\(/QCODE\\)\\{#.*?\\}") ){
        warning("WARNING: encoding error detected in document
                erroneous output is likely. Error was detected at:\n\t'",
                tag,"'\n")
      }
    }
}


#' Update codes data frame
#' Add discovered codes to the codes data frame
#'
#' @param codes_list A list of codes (usually from a coded document)
#' @param code_data_frame Existing data frame of QCODE codes
#' @param codes_df_path The path where the updated code data frame should be saved
#'
#' @export
add_discovered_code <- function(codes_list = "", code_data_frame = NULL , codes_df_path = "" ){
    code_data_frame <- as.data.frame(code_data_frame)
    old_codes <- as.character(code_data_frame[,"code"])
    new_codes <- unique(codes_list)
    code <- setdiff(new_codes, old_codes)
    if (length(code) > 0){
      code_id <- integer(length(code))
      code.description <- character(length(code))
      new_rows <- data.frame(code_id, code, code.description)

      code_data_frame <- rbind(code_data_frame, new_rows)
      row_n <- row.names(code_data_frame)
      code_data_frame$code_id[length(old_codes):
                      (length(old_codes) + length(code))] <-
        row_n[length(old_codes):(length(old_codes) + length(code))]

      saveRDS(code_data_frame, file = codes_df_path )
    }
}

#' Extract codes from text
#' Take coded text and extract the codes, assuming they are correctly formatted.
#' @param doc_text  The text data for a single document
#' @export
get_codes <- function(doc_text){
  codes <- stringr::str_extract_all(pattern = "\\{#.*?\\}", doc_text)
  codes <- unlist(stringi::stri_split_boundaries(codes[[1]], type = "word"))
  codes <- setdiff(codes, c("{", "}", "#", "", ",", " "))
  codes
}

#' Parse one document
#' @param doc A single row from a data frame containing document data
#' @param df The data frame that contains the parsed data
#' @param dots Other parameters that may be passed in.
#' @export
#  change df to something more meaningful
parse_one_document <- function(doc, df, dots){

  doc_id <- doc$doc_id
  #cat(paste("parsing document: ", doc_id, "\n"))

  #split the file on opening qcode tags
  #note: can't just use str_extract_all() with a nice clean regex, because qcodes can be nested
  splititems <- gsub("^$"," ",
                     unlist( strsplit( doc$document_text, "(\\(QCODE\\))") )
  )

  ### skip this document/row if no qcodes were found
  if( length(splititems) == 1 ){
    warning("WARNING: No QCODE blocks found in document ","\n")
    return()
  }

  error_check(doc$document_text)
  item_closed <- stringr::str_detect(splititems, "\\(/QCODE\\)\\{")
  splititems <- splititems[item_closed]

  # Nothing to see here.
  if (length(splititems) == 0){
    return(df)
  }
  sp <- unlist( strsplit( splititems, "\\(/QCODE\\)\\{")  )
  print(sp)
  ### iterate through the split items
  extra_depth <- 0

  for(i in 1:length(splititems)){

    #this is needed to handle directly-nested blocks (eg with no space/text between them)
    if (splititems[i] == ""){
      extra_depth <- extra_depth + 1
    }

    ### if we've found a qcode, process it
    # don't need now that we check earlier.
    # if( stringr::str_detect(splititems[i], "\\(/QCODE\\)\\{")){

      #split this entry on qcode close tags
      sp <- unlist( strsplit( splititems[i], "\\(/QCODE\\)\\{")  )

      ### iterate through the codes in found in this block
      for(level in length(sp):2){

        txt <- "" #will hold the entire text block to return for each qcode

        ### join up all the text fragments of this block for this level

        #first add the fragments in the outer splititems[] list, from before
        # we saw the '(/QCODE){' tag
        if(level > 1){
          for(j in (i-(level-1)-extra_depth):(i) ){
            txt <- paste0(txt, splititems[j])
          }

        } else if( level == 1 ) {
          #reset the extra_depth flag
          extra_depth <- 0
        }

        #then add the fragments in this inner sp[] list
        toadd <- stringr::str_match( sp, "^#.*\\}(.*)$" )[2]  #remove any qcode bits if there
        toadd[is.na(toadd)] <- sp[is.na(toadd)]

        txt <- paste0(txt, toadd)
        ### Clean up the text block & extract its codes

        # Remove nested tags from the text block to return
        txt <- stringr::str_replace_all(txt,"\\(\\/QCODE\\)\\{#.*?\\}","")

        #get the qcode(s) for this text block
        #the code block will be @ the start
        codes <- unlist( stringr::str_extract( sp[level], "^.*?\\}" ) )
        #split on the "#"
        codes <- unlist( strsplit(codes,"#") )

        #warn on qcode parsing error & remove blank first item if relevent
        if( is.na(codes[1]) ){
          warning(sep="",
                  "WARNING: encoding error detected in document ",doc_id,";
                  erroneous output is likely. Error was detected at:\n\t'",
                  sp[level],
                  "'\n")
          codes = c(NA,NA)
        } else if(codes[1] == ""){
          codes <- codes[2:length(codes)] #remove blank first vector item
        }

        #add the codes & matching text block to the df
        codes <- sapply(codes, function(x) stringr::str_replace(trimws(x), ",$|\\}$","") )
        #clean up code ends

        rowtoadd <- data.frame(doc = doc_id, qcode = as.factor(codes), text = txt)
        df <- rbind(df,rowtoadd)

        # Inefficient now because of the loop but eventually this should run on save (a single text).
        if (length("dots") > 0 & !is.null(dots$code_data_frame) & !is.null(dots$save_path) ) {
          qcoder::add_discovered_code(codes, dots$code_data_frame, dots$save_path)

        }
      }

   # } # close found code check

  }

  df
}
