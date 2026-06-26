package types

//FILE - MODEL TYPES REPORTS

//type - Report_MNG
type ReportMng struct {
	Sno          uint   `json:"sno" form:"sno"`
	Rpcode       string `json:"rpcode" form:"rpcode"`
	Dpid         uint   `json:"dpid" form:"dpid"`
	Rptid        uint   `json:"rptid" form:"rptid"`
	Is_Answered  bool   `json:"is_answered" form:"is_answered"`
	Is_Completed bool   `json:"is_completed" form:"is_completed"`
	Updatedate   string `json:"updatedate" form:"updatedate"`
	Depname      string `json:"depname" form:"depname"`
}

//type - Report
type Report struct {
	ID          uint64 `json:"id" form:"id"`
	Note        string `json:"note" form:"note"`
	Answer      string `json:"answer" form:"answer"`
	Rpcode      string `json:"rpcode" form:"rpcode"`
	Note_Time   string `json:"note_time" form:"note_time"`
	Answer_Time string `json:"answer_time" form:"answer_time"`
}

// type - Admin
// type Admin struct {
// 	AdminID  uint   `json:"adminid" form:"adminid"`
// 	Username string `json:"username" form:"username"`
// 	Password string `json:"password" form:"password"`
// }

//struct WorkUnit
type Department struct {
	Dpid  uint   `json:"dpid" form:"dpid"`
	Title string `json:"title" form:"title"`
}

// type - MailType
type ReportType struct {
	Rptid uint   `json:"rptid" form:"rptid"`
	Title string `json:"type" form:"type"`
}

// type - Email
type Email struct {
	Mailid  uint   `json:"mailid" form:"mailid"`
	Email   string `json:"email" form:"email"`
	Adminid uint   `json:"adminid" form:"adminid"`
}

// type - CombinedReport
type CombinedReport struct {
	ID           uint64 `json:"id"`
	Rpcode       string `json:"rpcode"`
	Note         string `json:"note"`
	Answer       string `json:"answer"`
	dpid         uint   `json:"dpid"`
	Rptid        uint   `json:"rptid"`
	Note_Time    string `json:"note_time"`
	Answer_Time  string `json:"answer_time"`
	Is_Answered  bool   `json:"is_answered"`
	Is_Completed bool   `json:"is_completed"`
	Updatedate   string `json:"updatedate"`
}
