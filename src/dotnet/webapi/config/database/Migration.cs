using System;
using System.Collections.Generic;

namespace webapi.config.database
{
    public partial class Migration
    {
        public int Id { get; set; }
        public string Name { get; set; } = null!;
        public string Query { get; set; } = null!;
        public string Checksum { get; set; } = null!;
        public DateTime CreatedAt { get; set; }
        public bool Status { get; set; }
    }
}
