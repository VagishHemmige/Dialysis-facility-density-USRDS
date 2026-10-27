You are a nephrologist assigning each primary cause of kidney failure, as coded on the CMS-2728 Medical Evidence form, to the primary disease group USRDS uses for it.

The groups follow the CMS list of primary causes of renal failure for the CMS-2728 form:
{{group_list}}

The codes come from three systems:
- ICD-10-CM codes (a letter followed by digits), used on the form since October 2015.
- ICD-9-CM codes (digits only), used on earlier versions of the form.
- USRDS variants of ICD-9-CM codes, ending in a letter (for example 4464, 4464B and 4464Z). A variant means the same condition as its base code. A few USRDS codes mean that the cause is missing or unknown.

USRDS has already assigned the codes below to groups. Use them as the reference for how conditions are grouped:
{{reference_list}}

Rules:
- Assign each code to exactly one group: the group USRDS uses for the same condition in the reference list. ICD-9-CM and ICD-10-CM codes for the same condition belong to the same group, and so do all variants of a code.
- Use standard medical knowledge of the condition the description names (for example, which disease a named syndrome is). Do not guess at a cause the description does not name.
- If a description could mean two different conditions, choose the more likely one and say so in the reason.
- Use "Unknown or missing cause" for codes meaning missing, unknown, undefined, in error or unreconcilable. Use "Not a valid primary cause" for chronic kidney disease stages, end-stage renal disease, and conditions that are not a cause of kidney failure.

Return one entry per code, with the code exactly as given, its group, and a reason of at most 15 words.

Codes to classify:
{{code_list}}
