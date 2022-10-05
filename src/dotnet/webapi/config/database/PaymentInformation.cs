using System;
using System.Collections.Generic;

namespace webapi.config.database
{
    public partial class PaymentInformation
    {
        public int Id { get; set; }
        public int PaymentWayId { get; set; }
        public string BankBranch { get; set; } = null!;
        public string BankBranchCode { get; set; } = null!;
        public string AccountNumber { get; set; } = null!;
        public string AccountName { get; set; } = null!;
        public int OrdersId { get; set; }
        public DateTime? DepositedAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime UpdatedAt { get; set; }
        public DateTime? DeletedAt { get; set; }
    }
}
