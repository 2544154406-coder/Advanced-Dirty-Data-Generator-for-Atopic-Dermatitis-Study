/***********************************************************************
 * Project: Advanced Dirty Data Generation (EDC-Proof Errors)
 * Scenario: Atopic Dermatitis Study
 * Focus: Logical inconsistencies, Protocol Deviations, Cross-domain conflicts
 * Sample Size: 300 Subjects
 * Fix: Replace RAND('integer',...) with FLOOR-based uniform integer generation
 ***********************************************************************/

options nodate nonumber ls=120 ps=60;
data _null_; call streaminit(98765); run;

data dm_advanced_dirty (keep=USUBJID SITEID AGE SEX RACE BRTHDT RFICDTC RFSTDTC 
                               TRT01P STRAT1_IGA_RANDOM STRAT1_IGA_BASELINE_ACTUAL 
                               STRAT2_BIO_PREV MH_PROSTATE_FLAG 
                               DSDECOD DSREASON_OTHER_TEXT EOSDT LAST_VISIT_DATE);
    
    length USUBJID $12 SITEID $3 COUNTRY $2 AGE 8 SEX $1 RACE $8;
    length BRTHDT RFICDTC RFSTDTC EOSDT LAST_VISIT_DATE $10;
    length TRT01P $10 STRAT1_IGA_RANDOM $1 STRAT1_IGA_BASELINE_ACTUAL $1 STRAT2_BIO_PREV $1;
    length MH_PROSTATE_FLAG $1; /* Y/N */
    length DSDECOD $20 DSREASON_OTHER_TEXT $100;
    
    do i = 1 to 300;
        
        /* --- 基础信息 (全部合法) --- */
        site_num = 100 + floor(20 * rand('uniform'));  /* 100~119 */
        SITEID = put(site_num, 3.);
        COUNTRY = 'US';
        
        USUBJID = catx('-', SITEID, put(i, z3.));
        
        AGE = 18 + floor(58 * rand('uniform'));  /* 18~75 */
        
        SEX = ifc(rand('uniform') < 0.5, 'M', 'F');
        RACE = 'WHITE';
        
        /* --- 脏数据点 1: 年龄计算不一致 --- */
        birth_year = 2026 - AGE;
        if rand('uniform') < 0.10 then do;
            /* 10%: 生日推算年龄与录入年龄相差1~2岁 */
            birth_year = birth_year + floor(2 * rand('uniform')) + 1; /* 1~2 */
        end;
        BRTHDT = catx('-', put(birth_year, 4.), '06', '15');
        
        /* --- 脏数据点 2: 日期逻辑陷阱 --- */
        base_day = 1 + floor(300 * rand('uniform'));  /* 1~300 */
        ref_date = '01JAN2025'd + base_day;
        RFICDTC = put(ref_date, yymmdd10.);
        
        if rand('uniform') < 0.08 then do;
            /* 8%: 给药日 = 知情同意日 */
            RFSTDTC = RFICDTC; 
        end;
        else do;
            RFSTDTC = put(ref_date + 1, yymmdd10.);
        end;
        
        /* --- 脏数据点 3: 分层因素冲突 --- */
        if rand('uniform') < 0.5 then STRAT1_IGA_RANDOM = '3';
        else STRAT1_IGA_RANDOM = '4';
        
        if rand('uniform') < 0.15 then do;
            /* 15%: 基线评估与随机化分层不一致 */
            if STRAT1_IGA_RANDOM = '4' then STRAT1_IGA_BASELINE_ACTUAL = '3';
            else STRAT1_IGA_BASELINE_ACTUAL = '4';
        end;
        else do;
            STRAT1_IGA_BASELINE_ACTUAL = STRAT1_IGA_RANDOM;
        end;
        
        /* --- 脏数据点 4: 性别与病史冲突 --- */
        MH_PROSTATE_FLAG = 'N';
        if SEX = 'M' and rand('uniform') < 0.10 then MH_PROSTATE_FLAG = 'Y';
        if SEX = 'F' and rand('uniform') < 0.05 then MH_PROSTATE_FLAG = 'Y'; /* 冲突 */
        
        /* --- 脏数据点 5: 既往生物制剂史 --- */
        STRAT2_BIO_PREV = ifc(rand('uniform') < 0.3, 'Y', 'N');
        
        /* --- 脏数据点 6: 退出原因自由文本滥用 --- */
        r_status = rand('uniform');
        if r_status < 0.80 then do;
            DSDECOD = 'COMPLETED';
            DSREASON_OTHER_TEXT = '';
            EOSDT = put(input(RFSTDTC, yymmdd10.) + 150, yymmdd10.);
            LAST_VISIT_DATE = EOSDT;
        end;
        else do;
            DSDECOD = 'DISCONTINUED';
            /* 退出日期：首次给药后 30~130 天 */
            EOSDT = put(input(RFSTDTC, yymmdd10.) + 30 + floor(101 * rand('uniform')), yymmdd10.);
            LAST_VISIT_DATE = EOSDT;
            
            if rand('uniform') < 0.60 then do;
                DSREASON_OTHER_TEXT = "Patient decided to stop due to personal reasons (moving job, no time)";
            end;
            else if rand('uniform') < 0.80 then do;
                DSREASON_OTHER_TEXT = "Physician decision: skin condition improved significantly, no need for study drug";
            end;
            else do;
                DSREASON_OTHER_TEXT = "Adverse Event: Headache (Subject felt it was related)";
            end;
        end;
        
        TRT01P = ifc(rand('uniform')<0.5, 'DRUG_A', 'PLACEBO');
        
        output;
    end;
    drop i site_num base_day ref_date r_iga r_status birth_year;
run;

/* --- 验证 --- */
proc print data=dm_advanced_dirty (obs=15);
    title "Advanced Dirty Data Examples (EDC-Proof)";
    var USUBJID AGE BRTHDT SEX MH_PROSTATE_FLAG 
        STRAT1_IGA_RANDOM STRAT1_IGA_BASELINE_ACTUAL 
        RFICDTC RFSTDTC DSREASON_OTHER_TEXT;
run;

/* --- 逻辑检查 --- */
data logic_checks;
    set dm_advanced_dirty;
    length Check_Type $40 Check_Detail $150;
    
    /* 检查1: 年龄 vs 生日 */
    if not missing(BRTHDT) then do;
        calc_age = 2026 - input(substr(BRTHDT, 1, 4), 4.);
        if abs(calc_age - AGE) > 1 then do;
            Check_Type = 'AGE_BIRTHDATE_MISMATCH';
            Check_Detail = cat('Age=', AGE, ', CalcAge=', calc_age, ', Birth=', BRTHDT);
            output;
        end;
    end;
    
    /* 检查2: 性别与病史 */
    if SEX = 'F' and MH_PROSTATE_FLAG = 'Y' then do;
        Check_Type = 'SEX_HISTORY_CONFLICT';
        Check_Detail = 'Female subject has Prostate Disease history';
        output;
    end;
    
    /* 检查3: 分层因子不一致 */
    if STRAT1_IGA_RANDOM ne STRAT1_IGA_BASELINE_ACTUAL then do;
        Check_Type = 'STRATIFICATION_MISMATCH';
        Check_Detail = cat('Rand_IGA=', STRAT1_IGA_RANDOM, ', Base_IGA=', STRAT1_IGA_BASELINE_ACTUAL);
        output;
    end;
    
    /* 检查4: 同日知情同意与给药 */
    if RFICDTC = RFSTDTC then do;
        Check_Type = 'SAME_DAY_IC_TX';
        Check_Detail = 'IC and First Dose on same day. Verify time stamps.';
        output;
    end;
    
    /* 检查5: 未编码退出原因 */
    if DSDECOD = 'DISCONTINUED' and length(DSREASON_OTHER_TEXT) > 0 then do;
        Check_Type = 'NON_CODED_WITHDRAWAL_REASON';
        Check_Detail = cat('Reason: "', DSREASON_OTHER_TEXT, '"');
        output;
    end;
run;

proc print data=logic_checks;
    title "Detected Logical Inconsistencies (Requires Manual Query)";
    var USUBJID Check_Type Check_Detail;
run;
