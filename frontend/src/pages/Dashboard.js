import { DataGrid } from '@mui/x-data-grid';
import React, { useEffect, useState } from 'react';

let hardcodedrows = [
    {
        id: 2,
        title: "tomato",
    },
    {
        id: 3,
        title: "potato",
    },
]


export default function Dashboard() {
    const [rows,setRows] = React.useState(hardcodedrows);
    const columns = [
        { 
            field: 'id', 
            headerName: 'ID', 
            width: 80,
            description: "A goal's unique 'id'entifier, or ID"
        },
      
        { 
            field: 'name', 
            headerName: 'Name', 
            flex: 0.5,
            minWidth: 200,
        },
        { 
            field: 'brand', 
            headerName: 'Brand', 
            flex: 0.5,
            minWidth: 200,
        },
        { 
            field: 'last_updated', 
            headerName: 'Last Updated', 
            flex: 0.5,
            minWidth: 200,
        },
        { 
            field: 'member_price', 
            headerName: 'Member Price', 
            flex: 0.5,
            minWidth: 200,
        },
        { 
            field: 'sale_price', 
            headerName: 'Sale Price', 
            flex: 0.5,
            minWidth: 200,
        },
        { 
            field: 'base_price', 
            headerName: 'Base Price', 
            flex: 0.5,
            minWidth: 200,
        },
        { 
            field: 'size', 
            headerName: 'Size', 
            flex: 0.5,
            minWidth: 200,
        },

    ]
   
    useEffect(() => {
        fetch(
            "http://localhost:8000/products",
            { 
              method: "GET",
              headers: { "content-type" : "application/json" },
            }
        ).then(response => response.json()
         .then( data => { console.log(data); setRows(data) }))
    }, []);
    return(
        <div style = {{backgroundColor: 'grey', width: '90%', borderRadius: 20}}>
            <div style={{ borderRadius: 4, height: 500, width: '80%'}}>
                <DataGrid
                    rows={rows}
                    columns={columns}
                />
                <p>hey</p>
            </div>
        </div>
    )  
}