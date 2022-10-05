using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;

namespace webapi.config.database
{
    public partial class databaseContext : DbContext
    {
        public databaseContext()
        {
        }

        public databaseContext(DbContextOptions<databaseContext> options)
            : base(options)
        {
        }

        public virtual DbSet<Migration> Migrations { get; set; } = null!;
        public virtual DbSet<NumTable> NumTables { get; set; } = null!;
        public virtual DbSet<NumThread> NumThreads { get; set; } = null!;

        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        {
            if (!optionsBuilder.IsConfigured)
            {
#warning To protect potentially sensitive information in your connection string, you should move it out of source code. You can avoid scaffolding the connection string by using the Name= syntax to read it from configuration - see https://go.microsoft.com/fwlink/?linkid=2131148. For more guidance on storing connection strings, see http://go.microsoft.com/fwlink/?LinkId=723263.
                optionsBuilder.UseNpgsql("Server=db;Database=database;Username=user;Password=pass");
            }
        }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {

            modelBuilder.Entity<Migration>(entity =>
            {
                entity.ToTable("_migrations");

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.Checksum)
                    .HasMaxLength(255)
                    .HasColumnName("checksum");

                entity.Property(e => e.CreatedAt)
                    .HasColumnType("timestamp without time zone")
                    .HasColumnName("created_at");

                entity.Property(e => e.Name)
                    .HasMaxLength(255)
                    .HasColumnName("name");

                entity.Property(e => e.Query).HasColumnName("query");

                entity.Property(e => e.Status).HasColumnName("status");
            });

            modelBuilder.Entity<NumTable>(entity =>
            {
                entity.HasNoKey();

                entity.ToTable("num_table");

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.Randomnumber).HasColumnName("randomnumber");
            });

            modelBuilder.Entity<NumThread>(entity =>
            {
                entity.HasNoKey();

                entity.ToTable("num_threads");

                entity.Property(e => e.Id).HasColumnName("id");

                entity.Property(e => e.Randomnumber).HasColumnName("randomnumber");
            });

            OnModelCreatingPartial(modelBuilder);
        }

        partial void OnModelCreatingPartial(ModelBuilder modelBuilder);
    }
}
